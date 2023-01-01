#include <stddef.h>

void* stb_zig_malloc(size_t size, void* userData);
void stb_zig_free(void* ptr, void* userData);
void stb_zig_assert(int expression);
size_t stb_zig_strlen(const char* str);
void* stb_zig_memcpy(void* dest, const void* src, size_t n);
void *stb_zig_memset(void* str, int c, size_t n);

#define STBTT_malloc(x,u)  stb_zig_malloc(x, u)
#define STBTT_free(x,u)    stb_zig_free(x, u)
#define STBTT_assert(x)    stb_zig_assert(x)
#define STBTT_strlen(x)    stb_zig_strlen(x)
#define STBTT_memcpy       stb_zig_memcpy
#define STBTT_memset       stb_zig_memset