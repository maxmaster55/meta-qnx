/*
 * Proof that bitbake can drive the QNX SDP toolchain: this is compiled by qcc
 * (not Yocto's cross-gcc) and staged into an IFS by mkifs, both from recipes.
 */
#include <stdio.h>
#include <sys/utsname.h>

int main(void)
{
	struct utsname u;

	printf("\n");
	printf("=========================================\n");
	printf(" Hello from QNX, built by Yocto/bitbake\n");

	if (uname(&u) == 0) {
		printf(" %s %s on %s\n", u.sysname, u.release, u.machine);
	} else {
		perror(" uname");
	}

	printf("=========================================\n");
	printf("\n");
	fflush(stdout);

	return 0;
}
