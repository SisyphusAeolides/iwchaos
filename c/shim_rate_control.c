// SPDX-License-Identifier: GPL-2.0-only
/*
 * iwchaos — chaos-informed rate control shim
 *
 * Selects an MCS (Modulation and Coding Scheme) index using the full
 * chaos parameter snapshot from the Rust engine.
 *
 * Rate selection algorithm:
 *
 *   The 802.11ax MCS table has indices 0–11 (MCS 0 = BPSK 1/2, MCS 11 = 1024-QAM 5/6).
 *   Standard minstrel-HT uses pure statistics. iwchaos replaces the rate
 *   selection with a chaos-steered lookup that considers:
 *
 *     1. Mandelbrot power state (coarse SNR band): maps [0,4] → rough MCS band
 *     2. Duffing SNR delta (fine perturbation): adjusts within the band
 *     3. Lyapunov exponent: gates aggressive MCS choices when λ₁ is high
 *        (high chaos → high uncertainty → prefer robust MCS)
 *     4. Logistic jitter: offsets the selection by a chaotic sub-step to
 *        break repeated collision patterns at the same MCS
 *
 * The Feigenbaum cascade depth of the logistic map determines how aggressive
 * the MCS jitter is: at cascade depth 7 (r≈4, full chaos), jitter covers
 * ±2 MCS steps; at depth 1 (periodic), jitter is ±0.
 */

#include <linux/kernel.h>
#include <linux/types.h>
#include "iwchaos_shim.h"

/*
 * iwchaos_rate_select - select an MCS index from the chaos parameter snapshot
 *
 * @cp:           chaos parameter snapshot (from iwchaos_update_all)
 * @n_rates:      number of entries in rate_table_mcs
 * @rate_table_mcs: array of supported MCS indices, sorted ascending by rate
 *
 * Returns an index into rate_table_mcs (not the MCS value itself).
 */
u8 iwchaos_rate_select(const struct iwchaos_chaos_params *cp,
                       u8 n_rates, const u8 *rate_table_mcs)
{
    int base_idx, delta_idx, jitter_idx, final_idx;
    int snr_db;

    if (!cp || !rate_table_mcs || n_rates == 0)
        return 0;

    /*
     * Step 1: Map Mandelbrot power state [0,4] to a base MCS band.
     *         power_state=0 → lowest quarter of table,
     *         power_state=4 → highest quarter.
     */
    base_idx = (int)cp->power_state * (int)(n_rates - 1) / 4;

    /*
     * Step 2: Apply Duffing SNR delta as a fine adjustment.
     *         snr_delta_centidecibels is in [-600, +600] (±6 dB).
     *         Each 2 dB ≈ one MCS step (conservative estimate).
     *         Convert: delta_idx = round(snr_delta_centidB / 200)
     */
    snr_db   = (int)cp->snr_delta_centidecibels;
    /* Add 100 before dividing to round toward zero symmetrically */
    if (snr_db >= 0)
        delta_idx = (snr_db + 100) / 200;
    else
        delta_idx = -((-snr_db + 100) / 200);

    /*
     * Step 3: Logistic jitter — ±1 step when Lyapunov exponent is moderate.
     *         When λ₁ is high (> 1.2), suppress jitter to prefer robustness.
     *         jitter maps [1, 100] µs → [-1, 0, +1] MCS step.
     */
    jitter_idx = 0;
    if (cp->lyapunov_est < 1.2 && cp->jitter_us > 0) {
        u32 j = cp->jitter_us;
        if (j < 34)
            jitter_idx = -1;
        else if (j > 66)
            jitter_idx = +1;
    }

    /*
     * Step 4: Combine and clamp to [0, n_rates-1].
     */
    final_idx = base_idx + delta_idx + jitter_idx;
    if (final_idx < 0)
        final_idx = 0;
    if (final_idx >= (int)n_rates)
        final_idx = (int)(n_rates - 1);

    return (u8)final_idx;
}

/*
 * iwchaos_rate_feedback - feed TX outcome back to the chaos engine
 *
 * @tx_success: 1 if the last frame was ACKed, 0 if it timed out
 * @snr_db:     measured SNR at the last TX in integer dB
 *
 * This function is a placeholder for the feedback path. In a full
 * implementation, it would update the Mandelbrot input coordinates
 * based on measured link quality, closing the chaos control loop.
 */
void iwchaos_rate_feedback(int tx_success, int snr_db)
{
    /*
     * TODO: Map (tx_success, snr_db) back to (snr_real, snr_imag) for
     * the next Mandelbrot evaluation. The mapping:
     *   snr_real = snr_db / 40.0  (normalise to Mandelbrot test radius ≈ 2)
     *   snr_imag = (1 - tx_success) * 0.5  (failure injects imaginary component)
     * would be implemented here and stored in the device state.
     */
    (void)tx_success;
    (void)snr_db;
}
