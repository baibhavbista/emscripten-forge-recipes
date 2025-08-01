/* Missing LAPACK infrastructure functions for WebAssembly build */
/* These are stub implementations to allow linking */

#include <float.h>
#include <math.h>

/* Machine parameters for double precision */
double dlamch_(char *cmach) {
    switch (*cmach) {
        case 'E': case 'e': /* Machine epsilon */
            return DBL_EPSILON;
        case 'S': case 's': /* Safe minimum */
            return DBL_MIN;
        case 'B': case 'b': /* Base of the machine */
            return 2.0;
        case 'P': case 'p': /* Precision = eps*base */
            return DBL_EPSILON * 2.0;
        case 'N': case 'n': /* Number of digits in mantissa */
            return DBL_MANT_DIG;
        case 'R': case 'r': /* Rounding mode */
            return 1.0;
        case 'M': case 'm': /* Minimum exponent */
            return DBL_MIN_EXP;
        case 'U': case 'u': /* Underflow threshold */
            return DBL_MIN;
        case 'L': case 'l': /* Largest exponent */
            return DBL_MAX_EXP;
        case 'O': case 'o': /* Overflow threshold */
            return DBL_MAX;
        default:
            return 0.0;
    }
}

/* Machine parameters for single precision */
float slamch_(char *cmach) {
    switch (*cmach) {
        case 'E': case 'e': return FLT_EPSILON;
        case 'S': case 's': return FLT_MIN;
        case 'B': case 'b': return 2.0f;
        case 'P': case 'p': return FLT_EPSILON * 2.0f;
        case 'N': case 'n': return FLT_MANT_DIG;
        case 'R': case 'r': return 1.0f;
        case 'M': case 'm': return FLT_MIN_EXP;
        case 'U': case 'u': return FLT_MIN;
        case 'L': case 'l': return FLT_MAX_EXP;
        case 'O': case 'o': return FLT_MAX;
        default: return 0.0f;
    }
}

/* ILAENV returns problem-dependent parameters */
int ilaenv_(int *ispec, char *name, char *opts, int *n1, int *n2, int *n3, int *n4) {
    /* Simplified implementation - return reasonable defaults */
    switch (*ispec) {
        case 1: /* Optimal blocksize */
            return 64;
        case 2: /* Minimum blocksize */
            return 2;
        case 3: /* Crossover point */
            return 128;
        default:
            return -1;
    }
}

/* LSAME tests if two characters are the same regardless of case */
int lsame_(char *ca, char *cb) {
    char cha = *ca;
    char chb = *cb;
    
    /* Convert to uppercase for comparison */
    if (cha >= 'a' && cha <= 'z') cha = cha - 'a' + 'A';
    if (chb >= 'a' && chb <= 'z') chb = chb - 'a' + 'A';
    
    return (cha == chb) ? 1 : 0;
}

/* XERBLA is the error handler */
int xerbla_(char *srname, int *info) {
    /* In WebAssembly, we'll just ignore errors for now */
    /* In a real implementation, you might want to throw an exception */
    return 0;
}