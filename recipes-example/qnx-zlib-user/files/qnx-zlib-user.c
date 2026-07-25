/* Links against the zlib staged by the qnx-autotools example, purely to prove
 * the sysroot handoff: this file #includes a header and calls a function from a
 * library another recipe built, reached through nothing but DEPENDS = "zlib". */
#include <stdio.h>
#include <string.h>
#include <zlib.h>

int main(void)
{
	const char *input = "the quick brown fox";
	unsigned char packed[64];
	uLongf packed_len = sizeof(packed);

	printf("linked against zlib %s\n", zlibVersion());

	if (compress(packed, &packed_len,
	             (const unsigned char *)input, strlen(input) + 1) != Z_OK) {
		fprintf(stderr, "compress() failed\n");
		return 1;
	}

	printf("compressed %zu bytes to %lu\n", strlen(input) + 1,
	       (unsigned long)packed_len);
	return 0;
}
