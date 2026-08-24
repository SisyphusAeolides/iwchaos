// Dummy math symbols to satisfy MODPOST without linking libgcc
double __adddf3(double a, double b) { return 0; }
double __subdf3(double a, double b) { return 0; }
double __muldf3(double a, double b) { return 0; }
double __divdf3(double a, double b) { return 0; }
int __gtdf2(double a, double b) { return 0; }
int __ltdf2(double a, double b) { return 0; }
int __gedf2(double a, double b) { return 0; }
int __ledf2(double a, double b) { return 0; }
int __eqdf2(double a, double b) { return 0; }
int __nedf2(double a, double b) { return 0; }
int __fixdfsi(double a) { return 0; }
unsigned long long __fixunsdfdi(double a) { return 0; }
double __floatundidf(unsigned long long a) { return 0; }
double cos(double a) { return 0; }
double log(double a) { return 0; }
double fmod(double a, double b) { return 0; }
double pow(double a, double b) { return 0; }
double __floatsidf(int a) { return 0; }
long long __fixdfdi(double a) { return 0; }
int __unorddf2(double a, double b) { return 0; }
