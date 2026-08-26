// SPDX-License-Identifier: GPL-2.0-only
/*
 * iwchaos — kernel-safe math runtime for freestanding Fortran objects
 *
 * gfortran -ffreestanding emits unresolved references to libm and libgcc
 * symbols. This file provides ring-0-safe implementations so the chaos
 * engine produces correct dynamics instead of degenerate zero stubs.
 *
 * Target: x86_64 with hardware FP in process context (ThinkPad P53).
 */

#include <linux/types.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

static double iwchaos_fabs(double x)
{
	return x < 0.0 ? -x : x;
}

static double iwchaos_reduce_pi(double x)
{
	const double two_pi = 2.0 * M_PI;
	double y = x;

	while (y > M_PI)
		y -= two_pi;
	while (y < -M_PI)
		y += two_pi;
	return y;
}

double cos(double x)
{
	double x2, x4, x6;

	x = iwchaos_reduce_pi(x);
	x2 = x * x;
	x4 = x2 * x2;
	x6 = x4 * x2;
	return 1.0 - 0.5 * x2 + x4 / 24.0 - x6 / 720.0;
}

double log(double x)
{
	double y, term;
	int exp2 = 0;

	if (x <= 0.0)
		return -1.0 / 0.0;
	if (x == 1.0)
		return 0.0;

	while (x >= 2.0) {
		x *= 0.5;
		exp2++;
	}
	while (x < 1.0) {
		x *= 2.0;
		exp2--;
	}

	y = (x - 1.0) / (x + 1.0);
	term = y;
	return 0.69314718055994530942 * exp2 +
	       2.0 * (y + term * y * y / 3.0 +
		      term * y * y * y * y / 5.0);
}

double sqrt(double x)
{
	double guess;
	int i;

	if (x <= 0.0)
		return 0.0;
	if (x == 1.0)
		return 1.0;

	guess = x;
	if (guess > 1.0)
		guess = x * 0.5;

	for (i = 0; i < 8; i++)
		guess = 0.5 * (guess + x / guess);

	return guess;
}

double exp(double x)
{
	double term = 1.0;
	double sum = 1.0;
	int i;

	for (i = 1; i < 20; i++) {
		term *= x / i;
		sum += term;
	}
	return sum;
}

double pow(double a, double b)
{
	int n;
	double result;

	if (b == 0.0)
		return 1.0;
	if (a == 0.0)
		return 0.0;
	if (b == 1.0)
		return a;
	if (b == 2.0)
		return a * a;

	n = (int)b;
	if ((double)n == b && n >= 0) {
		result = 1.0;
		while (n-- > 0)
			result *= a;
		return result;
	}

	return exp(b * log(a));
}

double fmod(double x, double y)
{
	if (y == 0.0)
		return 0.0 / 0.0;

	while (iwchaos_fabs(x) >= iwchaos_fabs(y))
		x -= (x > 0.0 ? y : -y);

	return x;
}

/* libgcc soft-float helpers — delegate to hardware FP on x86_64 */
double __adddf3(double a, double b) { return a + b; }
double __subdf3(double a, double b) { return a - b; }
double __muldf3(double a, double b) { return a * b; }
double __divdf3(double a, double b) { return a / b; }
int __gtdf2(double a, double b) { return a > b ? 1 : 0; }
int __ltdf2(double a, double b) { return a < b ? 1 : 0; }
int __gedf2(double a, double b) { return a >= b ? 1 : 0; }
int __ledf2(double a, double b) { return a <= b ? 1 : 0; }
int __eqdf2(double a, double b) { return a == b ? 1 : 0; }
int __nedf2(double a, double b) { return a != b ? 1 : 0; }
int __fixdfsi(double a) { return (int)a; }
unsigned long long __fixunsdfdi(double a)
{
	if (a <= 0.0)
		return 0ULL;
	return (unsigned long long)a;
}
double __floatundidf(unsigned long long a) { return (double)a; }
double __floatsidf(int a) { return (double)a; }
long long __fixdfdi(double a) { return (long long)a; }
int __unorddf2(double a, double b)
{
	return (a != a) || (b != b) ? 1 : 0;
}
