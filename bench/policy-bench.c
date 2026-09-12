// SPDX-License-Identifier: GPL-2.0-only

#define _POSIX_C_SOURCE 200809L

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

extern uint8_t iwchaos_chaos_rate_select_rust(uint8_t sta_id, uint8_t index,
						      int low, int high);
extern void iwchaos_chaos_tx_feedback_rust(uint8_t sta_id, int success,
						  int snr_db);

static uint64_t monotonic_ns(void)
{
	struct timespec now;

	clock_gettime(CLOCK_MONOTONIC, &now);
	return (uint64_t)now.tv_sec * 1000000000ULL + (uint64_t)now.tv_nsec;
}

int main(int argc, char **argv)
{
	uint64_t rounds = 10000000;
	volatile uint64_t checksum = 0;
	uint64_t start;

	if (argc == 2)
		rounds = strtoull(argv[1], NULL, 10);

	start = monotonic_ns();
	for (uint64_t i = 0; i < rounds; ++i) {
		uint8_t sta_id = (uint8_t)i;
		int success = (i & 7) != 0;
		int snr_db = success ? -48 : -82;

		iwchaos_chaos_tx_feedback_rust(sta_id, success, snr_db);
		checksum += iwchaos_chaos_rate_select_rust(sta_id, 5, 2, 8);
	}

	uint64_t elapsed = monotonic_ns() - start;
	printf("rounds=%llu elapsed_ns=%llu ns_per_round=%.2f checksum=%llu\n",
	       (unsigned long long)rounds,
	       (unsigned long long)elapsed,
	       (double)elapsed / (double)rounds,
	       (unsigned long long)checksum);
	return 0;
}
