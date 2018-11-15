
#include <vector>
#include <iostream>
#include <streambuf>
#include <cstdint>
#include <cstdlib>
#include <regex>
#include <set>
#include <unordered_set>

// The PICO-8 1-byte charset (excluding "\n")
std::string CHARSET = " 0123456789abcdefghijklmnopqrstuvwxyz!#%(){}[]<>+=/*:;.,~_";

// The input cart code
std::string INPUT;


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

    int score = 0;
};

int best_streak(int start_pos, context const &ctx)
{
    std::unordered_set<char> excluded = ctx.excluded;

    // Skip excluded chars until we reach EOF or a non-excluded char
    int best_len = 0;
    while (start_pos + best_len < (int)INPUT.size()
            && excluded.count(INPUT[start_pos + best_len]))
        ++best_len;

    // Check that _all_ skipped characters match the current LUT
    if (best_len > (int)ctx.prefix.size())
        return 0;
    for (int i = 0; i < best_len; ++i)
        if (ctx.prefix[ctx.prefix.size() - best_len + i] != INPUT[start_pos + i])
            return 0;

    // Count how many more characters match
    while (start_pos + best_len < (int)INPUT.size()
            && excluded.count(INPUT[start_pos + best_len]) == 0)
        excluded.insert(INPUT[start_pos + best_len++]);
    return best_len;
}

int global_best = 0;

void analyze(context const &ctx, int depth = 0)
{
    std::set<uint32_t> streaks;

    for (int pos = 0; pos < (int)INPUT.size(); ++pos)
    {
        int size = best_streak(pos, ctx);

        if (size >= 4)
        {
            int32_t val = pos;
            val += size << 16;
            streaks.insert(-val);
        }
    }

    if (streaks.size() == 0)
    {
        if (ctx.score > global_best)
        {
            global_best = ctx.score;
            std::string result = ctx.prefix;

            for (char c : CHARSET)
                if (ctx.excluded.count(c) == 0)
                    result += c;

            // Handle suffix
            result += ctx.suffix;

            printf("final string (score %d): \"%s\"\n", ctx.score, result.c_str());
        }
        return;
    }

    // Test all streaks
    int n = 0;
    for (auto val : streaks)
    {
        int pos = (-val) & ((1 << 16) - 1);
        int size = (-val) >> 16;

        if (depth < 2)
        {
            printf("[%d] testing streak %d/%d at %d: %d -- '%s'\n", depth, n, (int)streaks.size(), pos, size, INPUT.substr(pos, size).c_str());
            global_best = 0;
        }
        ++n;

        context newctx = ctx;
        newctx.score += size - 2;

        for (int i = 0; i < size; ++i)
            if (!newctx.excluded.count(INPUT[pos + i]))
            {
                newctx.prefix += INPUT.substr(pos + i, size - i).c_str();
                break;
            }

        for (int i = 0; i < size; ++i)
            newctx.excluded.insert(INPUT[pos + i]);

        analyze(newctx, depth + 1);
    }

}

std::map<char, int> frequencies;

int main()//int argc, char *argv[])
{
    INPUT = std::string{ std::istreambuf_iterator<char>(std::cin),
                         std::istreambuf_iterator<char>() };

    context ctx;

    ctx.prefix = ",i";
    ctx.suffix = "do t[sub(";

    // Exclude characters that would be encoded as multibyte
    for (char c : ctx.prefix + ctx.suffix)
        ctx.excluded.insert(c);

    // Replace inline strings with """""""… sequences so that
    // our stats don't get messed up by the contents of that string.
    for (int pos = 0, in_string = 0; pos < (int)INPUT.size(); ++pos)
    {
        ++frequencies[INPUT[pos]];

        if (INPUT[pos] == '"' && (pos == 0 || INPUT[pos - 1] != '\\'))
            in_string = 1 - in_string;
        if (in_string && !ctx.excluded.count(INPUT[pos]))
            INPUT[pos] = '"';
    }

    analyze(ctx);
}

