#include "llama.cpp/include/llama.h"
#include "llama.cpp/common/common.h"
#include <string>
#include <vector>
#include <cstring>
#include <functional>
#include <thread>

// Global state
static llama_model* g_model = nullptr;
static llama_context* g_ctx = nullptr;
static gpt_params g_params;

extern "C" {

// Initialize the runtime
int init_runtime(const char* model_dir, const char* quant_preset, int cpu_threads) {
    if (g_model) return 0; // Already initialized

    g_params.model = model_dir;
    g_params.n_threads = cpu_threads;
    g_params.n_ctx = 2048; // Default context window

    llama_backend_init();
    
    // Load model
    auto mparams = llama_model_default_params();
    g_model = llama_load_model_from_file(model_dir, mparams);
    
    if (!g_model) {
        return -1;
    }

    // Create context
    auto cparams = llama_context_default_params();
    cparams.n_ctx = g_params.n_ctx;
    cparams.n_threads = g_params.n_threads;
    
    g_ctx = llama_new_context_with_model(g_model, cparams);
    
    if (!g_ctx) {
        llama_free_model(g_model);
        g_model = nullptr;
        return -1;
    }

    return 0;
}

void shutdown_runtime() {
    if (g_ctx) llama_free(g_ctx);
    if (g_model) llama_free_model(g_model);
    g_ctx = nullptr;
    g_model = nullptr;
    llama_backend_free();
}

int create_conversation() {
    // In a stateless design, we might just reset the context or keep a system prompt.
    // For now, we return a dummy ID.
    if (g_ctx) {
        llama_kv_cache_clear(g_ctx);
    }
    return 1;
}

// Callback type definition
typedef void (*TokenCallback)(const char*);

int generate_reply(int conversation_id, const char* prompt, TokenCallback callback) {
    if (!g_ctx || !g_model) return -1;

    // Tokenize prompt
    std::vector<llama_token> tokens_list;
    tokens_list = ::llama_tokenize(g_ctx, prompt, true);

    // Evaluate prompt
    llama_batch batch = llama_batch_init(512, 0, 1);
    
    for (size_t i = 0; i < tokens_list.size(); i++) {
        llama_batch_add(batch, tokens_list[i], i, { 0 }, false);
    }
    // Last token needs to output logits
    batch.logits[batch.n_tokens - 1] = true;

    if (llama_decode(g_ctx, batch) != 0) {
        return -1;
    }

    int n_cur = batch.n_tokens;
    int n_decode = 0;
    const int max_tokens = 100; // Simplified limit

    while (n_decode < max_tokens) {
        // Sample next token
        auto n_vocab = llama_n_vocab(g_model);
        auto * logits = llama_get_logits_ith(g_ctx, batch.n_tokens - 1);

        // Greedy sampling for simplicity (can add temp/top_k later)
        llama_token new_token_id = 0;
        float max_prob = -1e9;
        
        for (int i = 0; i < n_vocab; i++) {
            if (logits[i] > max_prob) {
                max_prob = logits[i];
                new_token_id = i;
            }
        }

        // Check for EOS
        if (new_token_id == llama_token_eos(g_model)) {
            break;
        }

        // Convert token to string and callback
        std::string token_str = llama_token_to_piece(g_ctx, new_token_id);
        callback(token_str.c_str());

        // Prepare next batch
        llama_batch_clear(batch);
        llama_batch_add(batch, new_token_id, n_cur, { 0 }, true);
        
        n_cur++;
        n_decode++;

        if (llama_decode(g_ctx, batch) != 0) {
            break;
        }
    }

    llama_batch_free(batch);
    return 0;
}

}
