/*
 * A second application, whose only purpose is to demonstrate that adding one to
 * an image requires no edit to any image file -- just its name in
 * QNX_IFS_INSTALL.
 *
 * It prints what the QNX kernel reports about the machine it is running on.
 */
#include <stdio.h>
#include <unistd.h>
#include <sys/utsname.h>
#include <sys/neutrino.h>

int main(void)
{
	struct utsname u;

	printf("\n--- qnx-sysinfo ---\n");

	if (uname(&u) == 0) {
		printf(" system : %s %s\n", u.sysname, u.release);
		printf(" machine: %s\n", u.machine);
		printf(" node   : %s\n", u.nodename);
	} else {
		perror(" uname");
	}

	/* _SC_NPROCESSORS_ONLN reflects the vCPUs the hypervisor gave this guest. */
	printf(" cpus   : %ld\n", sysconf(_SC_NPROCESSORS_ONLN));
	printf(" pagesz : %ld\n", sysconf(_SC_PAGESIZE));
	printf("-------------------\n\n");

	fflush(stdout);
	return 0;
}
