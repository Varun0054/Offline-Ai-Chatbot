#include "llama.h"
#include "llama.h"
#include <string>
#include <vector>
#include <cstring>

static llama_model* g_model = nullptr;
static llama_context* g_ctx = nullptr;
static llama_sampler* g_sampler = nullptr;

static int g_threads = 2; // Optimized for mobile (big.LITTLE)
static int g_n_ctx = 2048; // Optimized for 4GB RAM devices

// Stop sequences for Qwen / ChatML
static std::vector<std::string> g_stop_strs = {
    "<|im_end|>",
    "<|im_start|>",
    "</s>",
    "<|endoftext|>",
    "User:", // Fallback
    "Assistant:", // Fallback
};

static std::string g_recent_output;
static int g_repeat_count = 0;



extern "C" {

// Helper function to add a token to the batch
void llama_batch_add(struct llama_batch & batch, llama_token id, llama_pos pos, const std::vector<llama_seq_id> & seq_ids, bool logits) {
    batch.token   [batch.n_tokens] = id;
    batch.pos     [batch.n_tokens] = pos;
    batch.n_seq_id[batch.n_tokens] = seq_ids.size();
    for (size_t i = 0; i < seq_ids.size(); ++i) {
        batch.seq_id[batch.n_tokens][i] = seq_ids[i];
    }
    batch.logits  [batch.n_tokens] = logits;

    batch.n_tokens++;
}

// ---------------------- INIT ------------------------------------

int init_runtime(const char* model_path, const char* quant_unused, int cpu_threads) {
    if (g_model) return 0;

    g_threads = cpu_threads;

    llama_backend_init();

    // --- Load Model ---
    llama_model_params mparams = llama_model_default_params();
    mparams.use_mmap = false; // Force load into RAM (Fastest)
    mparams.use_mlock = false; // Do NOT lock memory (causes crashes on some devices)
    
    g_model = llama_model_load_from_file(model_path, mparams);
    if (!g_model) {
        return -1;
    }

    // --- Create context ---
    llama_context_params cparams = llama_context_default_params();
    cparams.n_ctx = 1024; // Reduced context for speed
    cparams.n_batch = 1024;
    cparams.n_threads = g_threads;
    cparams.n_threads_batch = g_threads;
    cparams.flash_attn_type = LLAMA_FLASH_ATTN_TYPE_DISABLED;

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
    llama_sampler_chain_add(g_sampler, llama_sampler_init_top_p(0.95f, 1)); // Slightly higher Top-P for coherence
    llama_sampler_chain_add(g_sampler, llama_sampler_init_temp(0.6f)); // Lower Temp for less hallucination (more deterministic)
    llama_sampler_chain_add(g_sampler, llama_sampler_init_dist(1234));
    
    // Penalties: last_n=64, repeat=1.3, freq=0.6, present=0.4
    // Increased repeat penalty to 1.3 to strongly discourage loops
    llama_sampler_chain_add(g_sampler, llama_sampler_init_penalties(64, 1.3f, 0.6f, 0.4f));

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

static std::vector<llama_token> g_prev_tokens;

int start_completion(const char* prompt) {
    if (!g_ctx || !g_model) return -1;

    g_recent_output.clear(); 
    g_repeat_count = 0;

    const llama_vocab * vocab = llama_model_get_vocab(g_model);

    // Tokenize new prompt
    std::vector<llama_token> tokens;
    tokens.resize(strlen(prompt) + 32);

    int count = llama_tokenize(
        vocab,
        prompt,
        (int)strlen(prompt),
        tokens.data(),
        (int)tokens.size(),
        true,   // add BOS
        true    // parse special tokens
    );

    if (count < 0) return -1;
    
    if (count >= g_n_ctx) {
        count = g_n_ctx - 64; 
        if (count < 1) count = 1;
    }
    tokens.resize(count);

    // --- SMART KV CACHE REUSE ---
    int n_past = 0;
    
    // Find common prefix with previous tokens
    size_t common_len = 0;
    for (size_t i = 0; i < tokens.size() && i < g_prev_tokens.size(); i++) {
        if (tokens[i] == g_prev_tokens[i]) {
            common_len++;
        } else {
            break;
        }
    }
    
    // If we have a common prefix, we can reuse it!
    if (common_len > 0) {
        n_past = common_len;
        // Remove any KV cache beyond the common prefix
        // This effectively "rewinds" the state to just after the common part
        llama_memory_seq_rm(llama_get_memory(g_ctx), 0, n_past, -1);
    } else {
        // No match, clear everything
        llama_memory_clear(llama_get_memory(g_ctx), true);
    }
    
    // Update g_prev_tokens for next time
    g_prev_tokens = tokens;

    // Clean up previous batch
    if (g_batch.token) {
        llama_batch_free(g_batch);
    }

    // Init batch
    g_batch = llama_batch_init(g_n_ctx, 0, 1); 

    // Add ONLY NEW tokens to batch
    int n_eval = 0;
    for (int i = n_past; i < count; i++) {
        llama_batch_add(g_batch, tokens[i], i, { 0 }, false);
        n_eval++;
    }
    
    if (n_eval == 0) {
        // Edge case: Prompt is identical to previous? 
        // Should not happen in chat usually, but if so, just re-eval last token to get logits
        if (count > 0) {
             n_eval = 1;
             llama_batch_add(g_batch, tokens[count-1], count-1, { 0 }, true);
        }
    } else {
        // Set logits for the very last token
        g_batch.logits[n_eval - 1] = true; 
    }
    
    g_batch.n_tokens = n_eval;

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

    // 2. Aggressive Loop Detection - REMOVED for performance
    // The native sampler's repetition penalty is sufficient and much faster.
    
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
