// tokenizer.cpp — Minimal BPE tokenizer (reads vocab from GGUF)
//
// For v0.1: placeholder that works with known tokenizer formats.
// Production: use sentencepiece or tiktoken library.

#include "jllm_engine.h"
#include <string>
#include <vector>
#include <unordered_map>
#include <cstdio>

namespace jllm {

// Vocabulary loaded from GGUF metadata
struct Vocabulary {
    std::vector<std::string>              id_to_token;
    std::unordered_map<std::string, int>  token_to_id;
    int bos_id = 1;
    int eos_id = 2;
    int pad_id = 0;
};

static Vocabulary g_vocab;

bool load_tokenizer(const std::string& gguf_path) {
    // TODO: read tokenizer.ggml.tokens array from GGUF
    // For now, return false to indicate not yet implemented
    fprintf(stderr, "[tokenizer] GGUF tokenizer loading: TODO\n");
    fprintf(stderr, "[tokenizer] Workaround: use external tokenizer (sentencepiece/tiktoken)\n");
    return false;
}

std::vector<int> tokenize(const std::string& text) {
    // Placeholder: split by characters (wrong but functional for testing)
    std::vector<int> tokens;
    tokens.push_back(g_vocab.bos_id);
    for (char c : text) {
        auto it = g_vocab.token_to_id.find(std::string(1, c));
        if (it != g_vocab.token_to_id.end())
            tokens.push_back(it->second);
        else
            tokens.push_back(0);  // unknown
    }
    return tokens;
}

std::string detokenize(int token_id) {
    if (token_id >= 0 && token_id < (int)g_vocab.id_to_token.size())
        return g_vocab.id_to_token[token_id];
    return "";
}

std::string detokenize(const std::vector<int>& tokens) {
    std::string result;
    for (int id : tokens)
        result += detokenize(id);
    return result;
}

}  // namespace jllm
