#include "llama.h"
#include <string>
#include <vector>
#include <cstring>

static llama_model* g_model = nullptr;
static llama_context* g_ctx = nullptr;

static int g_threads = 4;
static int g_n_ctx = 512; // Reduced for 4GB RAM devices

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
    cparams.n_threads = g_threads;
    cparams.n_threads_batch = g_threads;

    g_ctx = llama_init_from_model(g_model, cparams);

    if (!g_ctx) {
        llama_model_free(g_model);
        g_model = nullptr;
        return -1;
    }

    return 0;
}

// ---------------------- SHUTDOWN ------------------------------------

void shutdown_runtime() {
    if (g_ctx) llama_free(g_ctx);
    if (g_model) llama_model_free(g_model);
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
        false   // no special parsing
    );

    if (count < 0) return -1;
    tokens.resize(count);

    // Clean up previous batch if needed
    if (g_batch.token) {
        llama_batch_free(g_batch);
    }

    // Init batch
    g_batch = llama_batch_init(2048, 0, 1); // Allocate enough for context

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
    if (!g_ctx || !g_model || !g_batch.token) return -1;

    const llama_vocab * vocab = llama_model_get_vocab(g_model);

    // Sample from last logits
    // Note: logits are only valid for the last token we processed
    // In start_completion, we set logits[count-1] = true
    // In continue_completion loop, we set logits[0] = true (since batch size is 1)
    
    // We need to find *where* the logits are. 
    // llama_get_logits_ith(ctx, i) returns logits for the i-th token in the *last batch*.
    // For prompt, it's n_tokens - 1.
    // For generation step, n_tokens is 1, so it's 0.
    
    auto * logits = llama_get_logits_ith(g_ctx, g_batch.n_tokens - 1);
    int n_vocab = llama_vocab_n_tokens(vocab);

    // Greedy sampling
    int best_token = 0;
    float best_val = -1e9f;
    for (int i = 0; i < n_vocab; i++) {
        if (logits[i] > best_val) {
            best_val = logits[i];
            best_token = i;
        }
    }

    if (best_token == llama_vocab_eos(vocab)) {
        return 0; // EOS
    }

    // Detokenize
    int res = llama_token_to_piece(vocab, best_token, buf, len, 0, false);
    if (res < 0) return -1;
    buf[res] = '\0';

    // Prepare next batch for the NEXT token
    // We reuse the same batch structure, just reset the count
    // But we don't need to re-allocate, just overwrite
    
    // IMPORTANT: llama_batch_init allocates arrays. We just write to index 0.
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
