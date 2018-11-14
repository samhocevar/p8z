
#include <vector>
#include <iostream>
#include <streambuf>
#include <cstdint>
#include <cstdlib>
#include <regex>
#include <unordered_set>

// The PICO-8 1-byte charset (excluding "\n")
std::string CHARSET = " 0123456789abcdefghijklmnopqrstuvwxyz!#%(){}[]<>+=/*:;.,~_";

int best_streak(std::string const &input, int start_pos, std::unordered_set<char> const &already_excluded)
{
    std::unordered_set<char> excluded = already_excluded;

    int best_len = 0;
    while (start_pos + best_len < (int)input.size()
            && excluded.count(input[start_pos + best_len]) == 0)
        excluded.insert(input[start_pos + best_len++]);
    return best_len;
}

std::map<char, int> frequencies;

int main()//int argc, char *argv[])
{
    auto input = std::string{ std::istreambuf_iterator<char>(std::cin),
                              std::istreambuf_iterator<char>() };

    std::string prefix = ",i";
    std::string suffix = "do t[sub(";

    // Exclude characters that would be encoded as multibyte
    std::unordered_set<char> excluded;
    for (char c : input)
        excluded.insert(c);
    for (char c : CHARSET)
        excluded.erase(c);
    for (char c : prefix + suffix)
        excluded.insert(c);

    // Replace inline strings with """"""" sequences
    for (int pos = 0, in_string = 0; pos < (int)input.size(); ++pos)
    {
        ++frequencies[input[pos]];

        if (input[pos] == '"' && (pos == 0 || input[pos - 1] != '\\'))
            in_string = 1 - in_string;
        if (in_string && !excluded.count(input[pos]))
            input[pos] = '"';
    }

    std::string result = prefix;

    for (int iter = 0; iter < 10; ++iter)
    {
        float best_score = 0;
        int best_pos = 0, best_size = 0;

        for (int pos = 0; pos < (int)input.size(); ++pos)
        {
            int size = best_streak(input, pos, excluded);

            if (size < 3)
                continue;

            float score = 0;
            for (int i = 0; i < size; ++i)
                score += 1.f / frequencies[input[pos + i]];

            //if (score > best_score)
            if (size > best_size)
            {
                best_score = score;
                best_pos = pos;
                best_size = size;
            }
        }

        printf("best position (%f) %d: %d -- '%s'\n",
               best_score, best_pos, best_size, input.substr(best_pos, best_size).c_str());

        result += input.substr(best_pos, best_size).c_str();

        for (int i = 0; i < best_size; ++i)
            excluded.insert(input[best_pos + i]);
    }

    for (char c : CHARSET)
        if (excluded.count(c) == 0)
            result += c;

    // Handle suffix
    result += suffix;

    printf("Final string: \"%s\"\n", result.c_str());
}

