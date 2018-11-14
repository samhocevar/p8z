
#include <vector>
#include <iostream>
#include <streambuf>
#include <cstdint>
#include <cstdlib>
#include <regex>
#include <unordered_set>

// The PICO-8 1-byte charset (excluding "\n")
std::string CHARSET = " 0123456789abcdefghijklmnopqrstuvwxyz!#%(){}[]<>+=/*:;.,~_";

struct context
{
    context()
    {
        for (int i = 0; i < 256; ++i)
            excluded.insert(i);
        for (char c : CHARSET)
            excluded.erase(c);
    }

    std::unordered_set<char> excluded;

    std::string prefix;
    std::string suffix;
};

int best_streak(std::string const &input, int start_pos, context const &ctx)
{
    std::unordered_set<char> excluded = ctx.excluded;

    // Skip excluded chars until we reach EOF or a non-excluded char
    int best_len = 0;
    while (start_pos + best_len < (int)input.size()
            && excluded.count(input[start_pos + best_len]))
        ++best_len;

    // Check that _all_ skipped characters match the current LUT
    if (best_len > (int)ctx.prefix.size())
        return 0;
    for (int i = 0; i < best_len; ++i)
        if (ctx.prefix[ctx.prefix.size() - best_len + i] != input[start_pos + i])
            return 0;

    // Count how many more characters match
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

    context ctx;

    ctx.prefix = ",i";
    ctx.suffix = "do t[sub(";

    // Exclude characters that would be encoded as multibyte
    for (char c : ctx.prefix + ctx.suffix)
        ctx.excluded.insert(c);

    // Replace inline strings with """""""… sequences so that
    // our stats don't get messed up by the contents of that string.
    for (int pos = 0, in_string = 0; pos < (int)input.size(); ++pos)
    {
        ++frequencies[input[pos]];

        if (input[pos] == '"' && (pos == 0 || input[pos - 1] != '\\'))
            in_string = 1 - in_string;
        if (in_string && !ctx.excluded.count(input[pos]))
            input[pos] = '"';
    }

    for (int iter = 0; iter < 10; ++iter)
    {
        float best_score = 0;
        int best_pos = 0, best_size = 0;

        for (int pos = 0; pos < (int)input.size(); ++pos)
        {
            int size = best_streak(input, pos, ctx);

            if (size < 3)
                continue;

            float score = 0;
            for (int i = 0; i < size; ++i)
                score += 1.f / frequencies[input[pos + i]];
            score *= size - 2;

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

        for (int i = 0; i < best_size; ++i)
            if (!ctx.excluded.count(input[best_pos + i]))
            {
                ctx.prefix += input.substr(best_pos + i, best_size - i).c_str();
                break;
            }

        for (int i = 0; i < best_size; ++i)
            ctx.excluded.insert(input[best_pos + i]);
    }

    std::string result = ctx.prefix;

    for (char c : CHARSET)
        if (ctx.excluded.count(c) == 0)
            result += c;

    // Handle suffix
    result += ctx.suffix;

    printf("Final string: \"%s\"\n", result.c_str());
}

