#include "llama.h"
#include "llama.h"
#include <string>
#include <vector>
#include <cstring>

static llama_model* g_model = nullptr;
static llama_context* g_ctx = nullptr;
static llama_sampler* g_sampler = nullptr;

static int g_threads = 4;
static int g_n_ctx = 2048;

// Stop sequences for TinyLlama / ChatML
static std::vector<std::string> g_stop_strs = {
    "<|im_end|>",
    "</s>",
    "<|assistant|>",
    "<|user|>",
    "<|system|>"
};

static std::string g_recent_output;
static int g_repeat_count = 0;



extern "C" {

// ---------------------- INIT ------------------------------------

int init_runtime(const char* model_path, const char* quant_unused, int cpu_threads) {
    if (g_model) return 0;

    g_threads = cpu_threads;

    llama_backend_init();

    // --- Load model ---
    llama_model_params mparams = llama_model_default_params();
    g_model = llama_model_load_from_file(model_path, mparams);

    if (!g_model) {
        return -1;
    }

    // --- Create context ---
    llama_context_params cparams = llama_context_default_params();
    cparams.n_ctx = g_n_ctx;
    cparams.n_batch = g_n_ctx; // Increase batch size to match context to prevent decode errors
    cparams.n_threads = g_threads;
    cparams.n_threads_batch = g_threads;
    cparams.flash_attn_type = LLAMA_FLASH_ATTN_TYPE_ENABLED; // Enable Flash Attention for speed

    g_ctx = llama_init_from_model(g_model, cparams);

    if (!g_ctx) {
        llama_model_free(g_model);
        g_model = nullptr;
        return -1;
    }

    // --- Initialize Sampler Chain ---
    auto sparams = llama_sampler_chain_default_params();
    g_sampler = llama_sampler_chain_init(sparams);
    
    // Add samplers: Top-K, Top-P, Temp, Dist (Random)
    llama_sampler_chain_add(g_sampler, llama_sampler_init_top_k(40));
    llama_sampler_chain_add(g_sampler, llama_sampler_init_top_p(0.9f, 1));
    llama_sampler_chain_add(g_sampler, llama_sampler_init_temp(0.8f));
    llama_sampler_chain_add(g_sampler, llama_sampler_init_dist(1234));
    
    // Penalties: last_n=64, repeat=1.2, freq=0.6, present=0.4 (User suggested values)
    llama_sampler_chain_add(g_sampler, llama_sampler_init_penalties(64, 1.2f, 0.6f, 0.4f));

    return 0;
}

// ---------------------- SHUTDOWN ------------------------------------

void shutdown_runtime() {
    if (g_sampler) llama_sampler_free(g_sampler);
    if (g_ctx) llama_free(g_ctx);
    if (g_model) llama_model_free(g_model);
    g_sampler = nullptr;
    g_ctx = nullptr;
    g_model = nullptr;
    llama_backend_free();
}

// ---------------------- CLEAR CACHE ------------------------------------

int create_conversation() {
    if (g_ctx) {
        llama_memory_clear(llama_get_memory(g_ctx), true);
    }
    return 1;
}

// ---------------------- GENERATION CALLBACK TYPE ------------------------------------

typedef void (*TokenCallback)(const char*);

// ---------------------- GENERATE ------------------------------------

// ---------------------- NON-BLOCKING GENERATION ------------------------------------

static llama_batch g_batch = {0};
static int g_n_cur = 0;

int start_completion(const char* prompt) {
    if (!g_ctx || !g_model) return -1;

    // Clear KV cache to ensure clean state for full prompt re-evaluation
    // Clear KV cache to ensure clean state for full prompt re-evaluation
    if (g_ctx) {
        llama_memory_clear(llama_get_memory(g_ctx), true);
    }
    
    g_recent_output.clear(); // Clear stop sequence buffer
    g_repeat_count = 0;

    const llama_vocab * vocab = llama_model_get_vocab(g_model);

    // Tokenize
    std::vector<llama_token> tokens;
    tokens.resize(strlen(prompt) + 32);

    int count = llama_tokenize(
        vocab,
        prompt,
        (int)strlen(prompt),
        tokens.data(),
        (int)tokens.size(),
        true,   // add BOS
        true    // parse special tokens (CRITICAL for ChatML tags like <|im_start|>)
    );

    if (count < 0) return -1;
    
    // Ensure we don't exceed context size
    if (count >= g_n_ctx) {
        // Truncate to leave space for generation (e.g., keep last g_n_ctx - 64 tokens)
        // For now, just error out or truncate simple
        count = g_n_ctx - 64; 
        if (count < 1) count = 1;
    }
    
    tokens.resize(count);

    // Clean up previous batch if needed
    if (g_batch.token) {
        llama_batch_free(g_batch);
    }

    // Init batch with size equal to context to be safe
    g_batch = llama_batch_init(g_n_ctx, 0, 1); 

    // Add prompt to batch
    for (int i = 0; i < count; i++) {
        g_batch.token[i] = tokens[i];
        g_batch.pos[i]   = i;
        g_batch.n_seq_id[i] = 1;
        g_batch.seq_id[i][0] = 0;
        g_batch.logits[i] = false;
    }
    g_batch.n_tokens = count;
    g_batch.logits[count - 1] = true; // Only compute logits for last token

    if (llama_decode(g_ctx, g_batch) != 0) {
        return -1;
    }

    g_n_cur = count;
    return 0;
}

int continue_completion(char* buf, int len) {
    if (!g_ctx || !g_model || !g_batch.token || !g_sampler) return -1;

    const llama_vocab * vocab = llama_model_get_vocab(g_model);

    // Sample using new API
    // -1 means sample from the last token's logits
    llama_token best_token = llama_sampler_sample(g_sampler, g_ctx, -1);
    
    // Accept the token (update internal state of samplers)
    llama_sampler_accept(g_sampler, best_token);

    if (best_token == llama_vocab_eos(vocab)) {
        return 0; // EOS
    }

    // Detokenize
    int res = llama_token_to_piece(vocab, best_token, buf, len, 0, false);
    if (res < 0) return -1;
    buf[res] = '\0';

    // --- Stop Sequence Checking ---
    g_recent_output += buf;
    // Keep buffer small to avoid memory issues, but long enough to catch stop tokens
    if (g_recent_output.length() > 200) {
        g_recent_output = g_recent_output.substr(g_recent_output.length() - 200);
    }

    // 1. Check for explicit stop strings
    for (const auto& stop_str : g_stop_strs) {
        if (g_recent_output.size() >= stop_str.size()) {
            if (g_recent_output.compare(
                    g_recent_output.size() - stop_str.size(),
                    stop_str.size(),
                    stop_str) == 0)
            {
                return 0; // STOP
            }
        }
    }

    // 2. Aggressive Loop Detection
    // Check if the last N characters are a repetition of the N characters before them
    // We check for repetition lengths from 5 to 50
    int text_len = g_recent_output.length();
    if (text_len > 20) {
        for (int pattern_len = 5; pattern_len <= 50 && pattern_len * 2 <= text_len; pattern_len++) {
            std::string p1 = g_recent_output.substr(text_len - pattern_len, pattern_len);
            std::string p2 = g_recent_output.substr(text_len - 2 * pattern_len, pattern_len);
            
            if (p1 == p2) {
                // Found a repetition!
                g_repeat_count++;
                if (g_repeat_count >= 3) {
                    // Repeated 3 times? Kill it.
                    return 0; 
                }
                // If it's a very long repetition (like a whole sentence), kill it sooner
                if (pattern_len > 20) {
                     return 0;
                }
                break; // Found a pattern, no need to check other lengths for this token
            } else {
                // Reset if we don't find a match at the very end? 
                // No, because we might be building a new pattern.
                // But we should reset g_repeat_count if we generated something NEW.
                // This logic is a bit tricky per-token.
                // Simplified: If we detect ANY repetition at the tail, we increment.
                // If we generate a token that breaks the repetition, we should zero it.
                // But 'p1 == p2' only checks immediate repetition.
            }
        }
    }

    // Prepare next batch for the NEXT token
    g_batch.n_tokens = 1;
    g_batch.token[0] = best_token;
    g_batch.pos[0] = g_n_cur;
    g_batch.n_seq_id[0] = 1;
    g_batch.seq_id[0][0] = 0;
    g_batch.logits[0] = true;

    g_n_cur++;

    // Decode the token we just sampled
    if (llama_decode(g_ctx, g_batch) != 0) {
        return -1;
    }

    return res; // Return length of string
}

void stop_completion() {
    if (g_batch.token) {
        llama_batch_free(g_batch);
        g_batch.token = nullptr; // Mark as freed
    }
}

}
