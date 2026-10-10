/*%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

 Module:       FGPropeller.cpp
 Author:       Jon S. Berndt
 Date started: 08/24/00
 Purpose:      Encapsulates the propeller object

 ------------- Copyright (C) 2000  Jon S. Berndt (jon@jsbsim.org) -------------

 This program is free software; you can redistribute it and/or modify it under
 the terms of the GNU Lesser General Public License as published by the Free Software
 Foundation; either version 2 of the License, or (at your option) any later
 version.

 This program is distributed in the hope that it will be useful, but WITHOUT
 ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public License for more
 details.

 You should have received a copy of the GNU Lesser General Public License along with
 this program; if not, write to the Free Software Foundation, Inc., 59 Temple
 Place - Suite 330, Boston, MA  02111-1307, USA.

 Further information about the GNU Lesser General Public License can also be found on
 the world wide web at http://www.gnu.org.

FUNCTIONAL DESCRIPTION
--------------------------------------------------------------------------------

HISTORY
--------------------------------------------------------------------------------
08/24/00  JSB  Created

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
INCLUDES
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%*/

#include "FGFDMExec.h"
#include "FGPropeller.h"
#include "input_output/FGXMLElement.h"
#include "input_output/FGLog.h"
#include <array>
#include <algorithm>
#include <cstdint>
#include <cstring>
#include <cfenv>
#include <cmath>
#include <limits>
#include <stdexcept>
#if defined(_M_IX86) || defined(_M_X64) || defined(__i386__) || defined(__x86_64__)
#include <xmmintrin.h>
#endif

using namespace std;

namespace JSBSim {

// Original project modification, 2026-10-09. Applicable enclosing LGPL terms.
// Opt-in method; qualification evidence maintained by consuming project.
namespace {
static_assert(std::numeric_limits<double>::is_iec559 &&
              std::numeric_limits<double>::digits == 53 &&
              std::numeric_limits<double>::max_exponent == 1024 &&
              std::numeric_limits<double>::min_exponent == -1021,
              "event-aware shaft requires IEEE binary64");

void ShaftReject(const char* reason) { throw std::runtime_error(reason); }

void ShaftEnvironment()
{
  if (std::fegetround() != FE_TONEAREST)
    ShaftReject("event-aware shaft: unsupported rounding mode");
#if defined(_M_IX86) || defined(_M_X64) || defined(__i386__) || defined(__x86_64__)
  // No environment mutation. x86/x64 qualify both SSE rounding and gradual
  // underflow before comparisons can misclassify subnormal inputs as zero.
  const unsigned csr = _mm_getcsr();
  if ((csr & (0x8000u | 0x0040u | 0x6000u)) != 0)
    ShaftReject("event-aware shaft: FTZ/DAZ or SSE rounding unsupported");
#else
  ShaftReject("event-aware shaft: floating-point control audit unavailable");
#endif
}

void ShaftFiniteNormalOrZero(double x)
{
  if (!std::isfinite(x) || (x != 0.0 && !std::isnormal(x)))
    ShaftReject("event-aware shaft: nonfinite or unsupported subnormal arithmetic");
}

// Nonzero source operands have unbiased exponents in [-100,100]. Holds are
// admitted before this narrower progress-domain test; malformed inputs are not.
void ShaftOperand(double x)
{
  ShaftFiniteNormalOrZero(x);
  if (x != 0.0 && (std::ilogb(x) < -100 || std::ilogb(x) > 100))
    ShaftReject("event-aware shaft: unsupported source exponent");
}

struct ShaftPair { double hi; double lo; };

ShaftPair ShaftTwoSum(double a, double b)
{
  // Round-to-nearest; no reassociation or implicit contraction. The reviewed
  // polynomial/residual lattices make every nonzero exact tail normal.
  const double s = a + b;
  ShaftFiniteNormalOrZero(s);
  const double bv = s - a;
  const double av = s - bv;
  const double br = b - bv;
  const double ar = a - av;
  const double e = ar + br;
  ShaftFiniteNormalOrZero(e);
  return {s, e};
}

ShaftPair ShaftTwoProduct(double a, double b)
{
  ShaftFiniteNormalOrZero(a);
  ShaftFiniteNormalOrZero(b);
  if (a == 0.0 || b == 0.0) return {0.0, 0.0};
  // Both significands have <=53 bits. Product residual quantum >=2^(ea+eb-104).
  // This conservative check excludes overflow AND residual underflow before FMA.
  const int exponent_sum = std::ilogb(a) + std::ilogb(b);
  if (exponent_sum < -900 || exponent_sum > 900)
    ShaftReject("event-aware shaft: unsupported error-free product range");
  const double p = a * b;
  const double e = std::fma(a, b, -p);
  ShaftFiniteNormalOrZero(p);
  ShaftFiniteNormalOrZero(e);
  return {p, e};
}

struct ShaftExpansion {
  // Zero-eliminating grow-expansion, increasing magnitude, exact sum.
  // Predicates need <=12 components; quotient residual needs <=14, not 32.
  std::array<double, 32> data{};
  unsigned size = 0;

  void grow(double value)
  {
    ShaftFiniteNormalOrZero(value);
    std::array<double, 32> next{};
    unsigned count = 0;
    double q = value;
    for (unsigned i = 0; i < size; ++i) {
      const ShaftPair pair = ShaftTwoSum(q, data[i]);
      if (pair.lo != 0.0) {
        if (count == next.size()) ShaftReject("event-aware shaft: expansion capacity");
        next[count++] = pair.lo;
      }
      q = pair.hi;
    }
    if (q != 0.0) {
      if (count == next.size()) ShaftReject("event-aware shaft: expansion capacity");
      next[count++] = q;
    }
    data = next;
    size = count;
  }

  int sign() const { return size == 0 ? 0 : (data[size-1] > 0.0 ? 1 : -1); }

  double estimate() const
  {
    double s = 0.0;
    for (unsigned i = 0; i < size; ++i) s = s + data[i];
    ShaftFiniteNormalOrZero(s);
    if ((sign() != 0 && s == 0.0) || (s != 0.0 && (s > 0.0 ? 1 : -1) != sign()))
      ShaftReject("event-aware shaft: unusable expansion reduction");
    return s;
  }

  void component(double value, int coefficient)
  {
    // All callers use +/-1 or +/-2; power-of-two scaling is exact in this domain.
    if (coefficient != 1 && coefficient != -1 && coefficient != 2 && coefficient != -2)
      ShaftReject("event-aware shaft: invalid internal coefficient");
    const double v = (coefficient == 2 || coefficient == -2)
                     ? std::ldexp(value, 1) : value;
    ShaftFiniteNormalOrZero(v);
    grow(coefficient < 0 ? -v : v);
  }

  void product2(double x, double y, int coefficient = 1)
  {
    const ShaftPair p = ShaftTwoProduct(x, y);
    component(p.lo, coefficient);
    component(p.hi, coefficient);
  }

  void product3(double x, double y, double z, int coefficient = 1)
  {
    const ShaftPair p = ShaftTwoProduct(x, y);
    product2(p.lo, z, coefficient);
    product2(p.hi, z, coefficient);
  }
};

double ShaftPositiveQuotient(const ShaftExpansion& numerator, double denominator)
{
  if (numerator.sign() <= 0 || !std::isfinite(denominator) || denominator <= 0.0)
    ShaftReject("event-aware shaft: invalid positive quotient");
  ShaftFiniteNormalOrZero(denominator);
  const double q1 = numerator.estimate() / denominator;
  ShaftFiniteNormalOrZero(q1);
  if (q1 <= 0.0) ShaftReject("event-aware shaft: positive quotient lost");
  // Exact residual n - q1*d, then one correction. No event predicate uses q1/q2.
  ShaftExpansion residual = numerator;
  residual.product2(q1, denominator, -1);
  const double q2 = residual.estimate() / denominator;
  ShaftFiniteNormalOrZero(q2);
  if (residual.sign() != 0 && q2 == 0.0)
    ShaftReject("event-aware shaft: quotient correction underflow");
  const double result = q1 + q2;
  ShaftFiniteNormalOrZero(result);
  if (result <= 0.0) ShaftReject("event-aware shaft: invalid corrected quotient");
  return result;
}

struct ShaftDecision { bool hold; double omega; };

ShaftDecision ShaftEventStep(double w, double power, double inertia, double h)
{
  ShaftEnvironment();
  if (!std::isfinite(w) || w < 0.0 ||
      !std::isfinite(power) || !std::isfinite(inertia) || inertia <= 0.0 ||
      !std::isfinite(h) || h < 0.0)
    ShaftReject("event-aware shaft: invalid inputs or rounding mode");
  // Preserve caller's original RPM, not a rounded omega conversion. Signed zeros
  // count as zero; source-exponent progress restrictions do not reject valid holds.
  if (h == 0.0 || power == 0.0) return {true, w};
  ShaftOperand(w); ShaftOperand(power); ShaftOperand(inertia); ShaftOperand(h);
  const double a = 0.01;
  double result = 0.0;
  if (power > 0.0) {
    ShaftExpansion budget;
    budget.product2(power, h);
    double base = w;
    if (w < a) {
      ShaftExpansion upward = budget;
      upward.product2(inertia, a, -1);
      upward.product2(inertia, w);
      if (upward.sign() < 0) {
        ShaftExpansion low = budget;
        low.product2(inertia, w);
        result = ShaftPositiveQuotient(low, inertia);
        if (result > a) ShaftReject("event-aware shaft: low growth boundary");
      } else if (upward.sign() == 0) {
        result = a;
      } else {
        budget = upward;
        base = a;
      }
      if (upward.sign() <= 0) {
        if (result < w) ShaftReject("event-aware shaft: positive monotonicity");
        return {false, result};
      }
    }
    const double impulse = ShaftPositiveQuotient(budget, inertia);
    const double twice = std::ldexp(impulse, 1);
    ShaftFiniteNormalOrZero(twice);
    result = std::hypot(base, std::sqrt(twice));
    if (result < base) ShaftReject("event-aware shaft: upper growth boundary");
  } else {
    const double q = -power;
    if (w > a) {
      ShaftExpansion down;
      down.product2(q, h, 2);
      down.product3(inertia, w, w, -1);
      down.product3(inertia, a, a);
      if (down.sign() < 0) {
        ShaftExpansion remainder;
        remainder.product3(inertia, w, w);
        remainder.product2(q, h, -2);
        result = std::sqrt(ShaftPositiveQuotient(remainder, inertia));
        if (result < a) ShaftReject("event-aware shaft: upper decay boundary");
      } else if (down.sign() == 0) {
        result = a;
      } else {
        ShaftExpansion stop = down;
        stop.product2(inertia, a, -2);
        if (stop.sign() >= 0) return {false, 0.0};
        ShaftExpansion low;
        low.product2(inertia, a, 2);
        for (unsigned i = 0; i < down.size; ++i) low.grow(-down.data[i]);
        result = ShaftPositiveQuotient(low, std::ldexp(inertia, 1));
        if (result > a) ShaftReject("event-aware shaft: crossed decay boundary");
      }
    } else {
      ShaftExpansion stop;
      stop.product2(q, h);
      stop.product2(inertia, w, -1);
      if (stop.sign() >= 0) return {false, 0.0};
      ShaftExpansion low;
      low.product2(inertia, w);
      low.product2(q, h, -1);
      result = ShaftPositiveQuotient(low, inertia);
      if (result > a) ShaftReject("event-aware shaft: low decay boundary");
    }
  }
  ShaftFiniteNormalOrZero(result);
  if (result < 0.0 || (power > 0.0 && result < w) || (power < 0.0 && result > w))
    ShaftReject("event-aware shaft: result monotonicity");
  if (result == 0.0) ShaftReject("event-aware shaft: unstated zero result");
  return {false, result};
}
// ADR015, original project modification. Existing held-power helper is unchanged.
// Fixed-capacity exact dyadics: all accepted predicates and event-time
// subtraction are integer operations, not rounded floating comparisons.
struct CoupledDyadic {
  std::array<std::uint32_t,128> limb{};
  unsigned size=0;
  int exponent=0, sign=0;

  explicit CoupledDyadic(double x=0.0) {
    ShaftFiniteNormalOrZero(x);
    if (x==0.0) return;
    std::uint64_t bits=0; std::memcpy(&bits,&x,sizeof bits);
    const std::uint64_t mantissa=(bits&0x000fffffffffffffull)|0x0010000000000000ull;
    limb[0]=static_cast<std::uint32_t>(mantissa);
    limb[1]=static_cast<std::uint32_t>(mantissa>>32);
    size=2; exponent=static_cast<int>((bits>>52)&0x7ff)-1023-52;
    sign=(bits>>63)?-1:1; normalize();
  }
  void normalize() {
    while (size && limb[size-1]==0) --size;
    if (!size) {sign=0; exponent=0; return;}
    while (limb[0]==0) {
      for(unsigned i=1;i<size;++i) limb[i-1]=limb[i];
      limb[--size]=0; exponent+=32;
    }
    while ((limb[0]&1u)==0) {
      for(unsigned i=0;i<size;++i)
        limb[i]=(limb[i]>>1)|((i+1<size?limb[i+1]:0u)<<31);
      ++exponent;
      while(size && limb[size-1]==0) --size;
    }
  }
  void shift(unsigned bits) {
    if (!size || !bits) return;
    const unsigned words=bits/32, tail=bits%32;
    if (words>=limb.size() || size+words+(tail?1u:0u)>limb.size())
      ShaftReject("coupled shaft: exact dyadic capacity");
    std::array<std::uint32_t,128> out{};
    for(unsigned i=0;i<size;++i) {
      const std::uint64_t v=static_cast<std::uint64_t>(limb[i])<<tail;
      out[i+words]|=static_cast<std::uint32_t>(v);
      if(tail) out[i+words+1]|=static_cast<std::uint32_t>(v>>32);
    }
    size+=words+(tail?1u:0u); limb=out;
    while(size && limb[size-1]==0) --size;
  }
  double approximation() const {
    if(!sign) return 0.0;
    double top=static_cast<double>(limb[size-1]);
    int scale=exponent+32*static_cast<int>(size-1);
    if(size>1) {top=std::ldexp(top,32)+limb[size-2]; scale-=32;}
    const double out=std::ldexp(top,scale)*sign;
    ShaftFiniteNormalOrZero(out);
    if(out==0.0) ShaftReject("coupled shaft: dyadic reduction underflow");
    return out;
  }
};

CoupledDyadic CNeg(CoupledDyadic a) {a.sign=-a.sign; return a;}
CoupledDyadic CScale(CoupledDyadic a,int e) {if(a.sign) a.exponent+=e; return a;}
CoupledDyadic CAdd(CoupledDyadic a,CoupledDyadic b) {
  if(!a.sign) return b;
  if(!b.sign) return a;
  const int common=std::min(a.exponent,b.exponent);
  a.shift(static_cast<unsigned>(a.exponent-common));
  b.shift(static_cast<unsigned>(b.exponent-common));
  a.exponent=b.exponent=common;
  const unsigned n=std::max(a.size,b.size);
  if(a.sign==b.sign) {
    std::uint64_t carry=0;
    for(unsigned i=0;i<n;++i) {
      const std::uint64_t v=static_cast<std::uint64_t>(a.limb[i])+b.limb[i]+carry;
      a.limb[i]=static_cast<std::uint32_t>(v); carry=v>>32;
    }
    a.size=n;
    if(carry) {
      if(n==a.limb.size()) ShaftReject("coupled shaft: exact sum capacity");
      a.limb[a.size++]=static_cast<std::uint32_t>(carry);
    }
  } else {
    int cmp=0;
    for(unsigned i=n;i>0;--i) if(a.limb[i-1]!=b.limb[i-1]) {
      cmp=a.limb[i-1]>b.limb[i-1]?1:-1; break;
    }
    if(!cmp) return CoupledDyadic();
    if(cmp<0) std::swap(a,b);
    std::uint64_t borrow=0;
    for(unsigned i=0;i<n;++i) {
      const std::uint64_t sub=static_cast<std::uint64_t>(b.limb[i])+borrow;
      const std::uint64_t old=a.limb[i];
      a.limb[i]=static_cast<std::uint32_t>(old-sub); borrow=old<sub?1:0;
    }
    if(borrow) ShaftReject("coupled shaft: internal exact subtraction");
    a.size=n;
  }
  a.normalize(); return a;
}
CoupledDyadic CSub(const CoupledDyadic& a,const CoupledDyadic& b) {return CAdd(a,CNeg(b));}
CoupledDyadic CMul(const CoupledDyadic& a,const CoupledDyadic& b) {
  if(!a.sign || !b.sign) return CoupledDyadic();
  if(a.size+b.size>a.limb.size()) ShaftReject("coupled shaft: exact product capacity");
  CoupledDyadic out; out.sign=a.sign*b.sign; out.exponent=a.exponent+b.exponent;
  out.size=a.size+b.size;
  for(unsigned i=0;i<a.size;++i) {
    std::uint64_t carry=0;
    for(unsigned j=0;j<b.size;++j) {
      const std::uint64_t v=static_cast<std::uint64_t>(a.limb[i])*b.limb[j]
                            +out.limb[i+j]+carry;
      out.limb[i+j]=static_cast<std::uint32_t>(v); carry=v>>32;
    }
    out.limb[i+b.size]=static_cast<std::uint32_t>(carry);
  }
  out.normalize(); return out;
}
int CCompare(const CoupledDyadic& a,const CoupledDyadic& b) {return CSub(a,b).sign;}
struct CoupledRatio {
  CoupledDyadic n,d;
  CoupledRatio(CoupledDyadic numerator,CoupledDyadic denominator)
    :n(numerator),d(denominator) {
    if(!d.sign) ShaftReject("coupled shaft: zero exact denominator");
    if(d.sign<0) {n=CNeg(n);d=CNeg(d);}
  }
};
int CCompare(const CoupledRatio& a,const CoupledRatio& b) {
  return CCompare(CMul(a.n,b.d),CMul(b.n,a.d));
}
CoupledRatio CSubtract(const CoupledRatio& a,const CoupledRatio& b) {
  return CoupledRatio(CSub(CMul(a.n,b.d),CMul(b.n,a.d)),CMul(a.d,b.d));
}

void CoupledOperand(double x) {
  ShaftFiniteNormalOrZero(x);
  if(x!=0.0 && (std::ilogb(x)<-60 || std::ilogb(x)>60))
    ShaftReject("coupled shaft: unsupported operand exponent");
}
double CoupledRounded(double x) {CoupledOperand(x); return x;}
struct CoupledPolynomial {std::array<CoupledDyadic,5> c{}; unsigned degree=0;};
CoupledDyadic CEval(const CoupledPolynomial& p,const CoupledDyadic& x) {
  CoupledDyadic v=p.c[p.degree];
  for(unsigned i=p.degree;i>0;--i) v=CAdd(CMul(v,x),p.c[i-1]);
  return v;
}
void CTrim(CoupledPolynomial& p) {while(p.degree && !p.c[p.degree].sign) --p.degree;}
struct CoupledLaw {double c0,c1,c2,c3;};
CoupledPolynomial CTorquePolynomial(const CoupledLaw& p) {
  CoupledPolynomial out;
  if(p.c0==0.0) {out.c[0]=CoupledDyadic(p.c1);out.c[1]=CoupledDyadic(p.c2);
    out.c[2]=CoupledDyadic(p.c3);out.degree=2;}
  else {out.c[0]=CoupledDyadic(p.c0);out.c[1]=CoupledDyadic(p.c1);
    out.c[2]=CoupledDyadic(p.c2);out.c[3]=CoupledDyadic(p.c3);out.degree=3;}
  CTrim(out); return out;
}
CoupledPolynomial CDerivativePolynomial(const CoupledLaw& p) {
  CoupledPolynomial out;
  if(p.c0==0.0) {out.c[0]=CoupledDyadic(p.c2);out.c[1]=CScale(CoupledDyadic(p.c3),1);out.degree=1;}
  else {out.c[0]=CoupledDyadic(-p.c0);out.c[2]=CoupledDyadic(p.c2);
    out.c[3]=CScale(CoupledDyadic(p.c3),1);out.degree=3;}
  CTrim(out); return out;
}
double CRootBound(const CoupledPolynomial& p) {
  if(!p.degree) ShaftReject("coupled shaft: constant polynomial needs no bound");
  // approximation is only a proposal; exact comparisons certify the outward
  // ratios below, including all effective-degree/zero leading-coefficient cases.
  const CoupledDyadic lead=p.c[p.degree].sign<0?CNeg(p.c[p.degree]):p.c[p.degree];
  double largest=0.0;
  for(unsigned i=0;i<p.degree;++i) if(p.c[i].sign) {
    CoupledDyadic n=p.c[i].sign<0?CNeg(p.c[i]):p.c[i];
    double r=CoupledRounded(n.approximation()/lead.approximation());
    bool enclosed=false;
    for(unsigned j=0;j<8;++j) {
      if(CCompare(CMul(CoupledDyadic(r),lead),n)>=0) {enclosed=true;break;}
      r=std::nextafter(r,std::numeric_limits<double>::infinity());CoupledOperand(r);
    }
    if(!enclosed) ShaftReject("coupled shaft: outward root-bound ratio");
    largest=std::max(largest,r);
  }
  double bound=CoupledRounded(1.0+largest);
  if(CCompare(CoupledDyadic(bound),CAdd(CoupledDyadic(1.0),CoupledDyadic(largest)))<0)
    bound=CoupledRounded(std::nextafter(bound,std::numeric_limits<double>::infinity()));
  return bound;
}
struct CoupledBracket {double lo,hi;};
CoupledBracket CIsolate(const CoupledPolynomial& p,double lo,double hi) {
  const int left=CEval(p,CoupledDyadic(lo)).sign;
  const int right=CEval(p,CoupledDyadic(hi)).sign;
  if(!left) return {lo,lo};
  if(!right) return {hi,hi};
  if(left==right || !(lo<hi)) ShaftReject("coupled shaft: invalid root bracket");
  for(unsigned i=0;i<64;++i) {
    if(std::nextafter(lo,hi)==hi) return {lo,hi};
    const double m=CoupledRounded(lo+(hi-lo)*0.5);
    if(!(m>lo && m<hi)) ShaftReject("coupled shaft: root bracket stagnation");
    const int s=CEval(p,CoupledDyadic(m)).sign;
    if(!s) return {m,m};
    if(s==left) lo=m; else hi=m;
  }
  if(std::nextafter(lo,hi)==hi) return {lo,hi};
  ShaftReject("coupled shaft: 64 root bisections exhausted"); return {0,0};
}
struct CoupledInterval {CoupledDyadic lo,hi;};
CoupledInterval CIAdd(const CoupledInterval& a,const CoupledInterval& b) {
  return {CAdd(a.lo,b.lo),CAdd(a.hi,b.hi)};
}
CoupledInterval CIMul(const CoupledInterval& a,const CoupledInterval& b) {
  const std::array<CoupledDyadic,4> v{{CMul(a.lo,b.lo),CMul(a.lo,b.hi),CMul(a.hi,b.lo),CMul(a.hi,b.hi)}};
  CoupledInterval out{v[0],v[0]};
  for(unsigned i=1;i<4;++i) {if(CCompare(v[i],out.lo)<0) out.lo=v[i];if(CCompare(v[i],out.hi)>0) out.hi=v[i];}
  return out;
}
CoupledInterval CIEval(const CoupledPolynomial& p,double lo,double hi) {
  CoupledInterval v{p.c[p.degree],p.c[p.degree]},x{CoupledDyadic(lo),CoupledDyadic(hi)};
  for(unsigned i=p.degree;i>0;--i) v=CIAdd(CIMul(v,x),{p.c[i-1],p.c[i-1]});
  return v;
}
CoupledPolynomial CTimeDerivative(const CoupledLaw& p,double w0) {
  const CoupledDyadic w(w0),w2=CMul(w,w),w3=CMul(w2,w),w4=CMul(w2,w2);
  const CoupledDyadic a=CAdd(CoupledDyadic(p.c1),CMul(CoupledDyadic(p.c2),w));
  CoupledPolynomial b;b.degree=4;
  b.c[0]=CAdd(CScale(CMul(a,w2),-2),CScale(CMul(CMul(CoupledDyadic(p.c3),w4),CoupledDyadic(3.0)),-4));
  b.c[1]=CAdd(CoupledDyadic(p.c0),CScale(CAdd(CMul(a,w),CMul(CoupledDyadic(p.c3),w3)),-1));
  b.c[2]=CAdd(CScale(a,-2),CScale(CMul(CMul(CoupledDyadic(p.c3),w2),CoupledDyadic(3.0)),-3));
  b.c[4]=CScale(CoupledDyadic(-p.c3),-4);
  CTrim(b);
  // Factor exact endpoint zeros at x=0; x>0 preserves the sign. This proves
  // constant-power-loss B=c0*x without a rounded endpoint comparison.
  while(b.degree && !b.c[0].sign) {for(unsigned i=0;i<b.degree;++i)b.c[i]=b.c[i+1];b.c[b.degree]=CoupledDyadic();--b.degree;}
  return b;
}
void CCertifyDecay(const CoupledLaw& p,double w0,double endpoint) {
  const CoupledPolynomial b=CTimeDerivative(p,w0);
  std::array<CoupledBracket,9> work{};unsigned count=1,splits=0;
  work[0]={endpoint,w0};
  while(count) {
    unsigned selected=0;
    for(unsigned i=1;i<count;++i)
      if(work[i].hi-work[i].lo>work[selected].hi-work[selected].lo ||
         (work[i].hi-work[i].lo==work[selected].hi-work[selected].lo && work[i].lo<work[selected].lo)) selected=i;
    const CoupledBracket interval=work[selected];work[selected]=work[--count];
    const CoupledInterval range=CIEval(b,interval.lo,interval.hi);
    if(range.hi.sign<=0 && range.lo.sign<0) continue;
    if(range.lo.sign>0 || splits==8) ShaftReject("coupled shaft: decay continuation uncertified");
    const double m=CoupledRounded(interval.lo+(interval.hi-interval.lo)*0.5);
    if(!(m>interval.lo && m<interval.hi)) ShaftReject("coupled shaft: decay certificate stagnation");
    work[count++]={interval.lo,m};work[count++]={m,interval.hi};++splits;
  }
}
CoupledRatio CTime(const CoupledLaw& p,double inertia,double w0,double x) {
  const CoupledDyadic start(w0),end(x),m=CScale(CAdd(start,end),-1);
  CoupledDyadic numerator=CMul(CoupledDyadic(inertia),CSub(end,start));
  const CoupledDyadic denominator=CEval(CTorquePolynomial(p),m);
  if(p.c0!=0.0) numerator=CMul(numerator,m);
  CoupledRatio t(numerator,denominator);
  if(t.n.sign<=0) ShaftReject("coupled shaft: nonpositive continuation time");
  return t;
}
double CRatioFloor(const CoupledRatio& value,bool squareRoot=false) {
  if(value.n.sign<=0) ShaftReject("coupled shaft: invalid positive analytic result");
  double x=CoupledRounded(value.n.approximation()/value.d.approximation());
  if(squareRoot) x=CoupledRounded(std::sqrt(x));
  for(unsigned i=0;i<8;++i) {
    const double next=CoupledRounded(std::nextafter(x,std::numeric_limits<double>::infinity()));
    CoupledDyadic a(x),b(next);
    if(squareRoot) {a=CMul(a,a);b=CMul(b,b);}
    if(CCompare(CMul(a,value.d),value.n)>0) {x=CoupledRounded(std::nextafter(x,0.0));continue;}
    if(CCompare(CMul(b,value.d),value.n)<=0) {x=next;continue;}
    return x;
  }
  ShaftReject("coupled shaft: analytic enclosure correction exhausted");return 0;
}
double CSolve(const CoupledLaw& p,double inertia,double w0,double endpoint,const CoupledRatio& h,int drift) {
  if(p.c0==0.0 && p.c2==0.0 && p.c3==0.0) {
    const CoupledDyadic numerator=CAdd(CMul(CMul(CoupledDyadic(inertia),CoupledDyadic(w0)),h.d),CMul(h.n,CoupledDyadic(p.c1)));
    return CRatioFloor(CoupledRatio(numerator,CMul(CoupledDyadic(inertia),h.d)));
  }
  if(p.c0<0.0 && p.c1==0.0 && p.c2==0.0 && p.c3==0.0) {
    const CoupledDyadic numerator=CAdd(CMul(CMul(CMul(CoupledDyadic(inertia),CoupledDyadic(w0)),CoupledDyadic(w0)),h.d),CScale(CMul(h.n,CoupledDyadic(p.c0)),1));
    return CRatioFloor(CoupledRatio(numerator,CMul(CoupledDyadic(inertia),h.d)),true);
  }
  double lo=std::min(w0,endpoint),hi=std::max(w0,endpoint);
  for(unsigned i=0;i<64;++i) {
    if(std::nextafter(lo,hi)==hi) return lo;
    const double m=CoupledRounded(lo+(hi-lo)*0.5);
    if(!(m>lo && m<hi)) ShaftReject("coupled shaft: continuation stagnation");
    const int cmp=CCompare(CTime(p,inertia,w0,m),h);
    if(!cmp) return m;
    if(cmp*drift<0) lo=m;else hi=m;
  }
  if(std::nextafter(lo,hi)==hi) return lo;
  ShaftReject("coupled shaft: 64 continuation bisections exhausted");return 0;
}

struct CoupledAdvance {
  double w;
  bool source_event, stop, hold;
  CoupledRatio remaining;
};
// Source-extraction test seam: immutable scalar law, not a production property
// or generic model callback. Actual frames remain topology-checked by the class.
CoupledAdvance CAdvanceSegment(const CoupledLaw& p,double inertia,double w,
                              const CoupledRatio& remaining,bool hasEndpoint,double endpoint)
{
  ShaftEnvironment();
  for(double c:{p.c0,p.c1,p.c2,p.c3,inertia,w}) CoupledOperand(c);
  if(p.c0>0.0 || p.c3>0.0 || inertia<=0.0 || w<0.0 || remaining.n.sign<0)
    ShaftReject("coupled shaft: invalid scalar segment");
  if(!remaining.n.sign) return {w,false,false,true,remaining};
  const int drift=CEval(CTorquePolynomial(p),CoupledDyadic(w)).sign;
  if(!drift || (w==0.0 && drift<0)) return {w,false,false,true,remaining};
  if(hasEndpoint) {
    CoupledOperand(endpoint);
    if(!(drift>0?endpoint>w:endpoint<w)) ShaftReject("coupled shaft: invalid source endpoint");
  }
  bool equilibrium=false,sourceEvent=hasEndpoint;
  const CoupledPolynomial torque=CTorquePolynomial(p);
    if(drift>0 && !hasEndpoint) {
      if(!torque.degree) {
        return {CSolve(p,inertia,w,w,remaining,drift),false,false,false,remaining};
      }
      endpoint=CRootBound(torque);hasEndpoint=true;
      if(!(endpoint>w)) ShaftReject("coupled shaft: no finite growth bracket");
    }
    if(drift<0 && !hasEndpoint) endpoint=0.0;
    const int endSign=CEval(torque,CoupledDyadic(endpoint)).sign;
    if(!endSign) equilibrium=true;
    else if(endSign!=drift) {
      const CoupledBracket root=CIsolate(torque,std::min(w,endpoint),std::max(w,endpoint));
      endpoint=drift>0?root.lo:root.hi;equilibrium=true;sourceEvent=false;
    } else if(drift<0) {
      const CoupledPolynomial derivative=CDerivativePolynomial(p);
      if(CEval(derivative,CoupledDyadic(endpoint)).sign>0 && CEval(derivative,CoupledDyadic(w)).sign<0) {
        const CoupledBracket peak=CIsolate(derivative,endpoint,w);
        const CoupledInterval peakValue=CIEval(torque,peak.lo,peak.hi);
        if(peakValue.lo.sign>0) {
          const CoupledBracket root=CIsolate(torque,peak.hi,w);
          endpoint=root.hi;equilibrium=true;sourceEvent=false;
        } else if(peakValue.hi.sign>=0) ShaftReject("coupled shaft: unresolved tangent equilibrium");
      }
    }
    if(!(drift>0?endpoint>w:endpoint<w)) ShaftReject("coupled shaft: empty continuation interval");
    if(drift<0) CCertifyDecay(p,w,endpoint);
    const CoupledRatio eventTime=CTime(p,inertia,w,endpoint);
    const int timeOrder=CCompare(remaining,eventTime);
    if(equilibrium && timeOrder>=0) ShaftReject("coupled shaft: finite equilibrium arrival or uncertain ordering");
    if(timeOrder<0) {
      const double result=CSolve(p,inertia,w,endpoint,remaining,drift);
      if(result<0.0 || (drift>0 && result<w) || (drift<0 && result>w)) ShaftReject("coupled shaft: nonmonotone result");
      return {result,false,false,false,remaining};
    }
    if(endpoint==0.0) {
      if(!(p.c0<0.0 || (p.c0==0.0 && p.c1<0.0))) ShaftReject("coupled shaft: asymptotic zero is not a stop");
      return {0.0,false,true,false,CSubtract(remaining,eventTime)};
    }
    if(!sourceEvent) ShaftReject("coupled shaft: finite bracket exhausted");
  return {endpoint,true,false,false,CSubtract(remaining,eventTime)};
}

CoupledLaw CBuildLaw(const CoupledShaftFrameV1& f,double w,double cpKnot,double L,double A,int direction) {
  CoupledLaw p{f.engine_c0_ftlb_per_s,f.engine_c1_ftlb,f.engine_c2_ftlb_s,0.0};
  const bool lowCP=A>0.0 && (w<cpKnot || (w==cpKnot && direction<0));
  p.c3=CoupledRounded(-(lowCP?0.02:0.06)*L);
  if(A>0.0 && !lowCP) p.c2=CoupledRounded(p.c2+CoupledRounded(CoupledRounded(0.02*A)*L));
  const bool starter=f.mode==ShaftOperatingModeV1::cranking &&
      (w<f.starter_limit_w_radps || (w==f.starter_limit_w_radps && direction<0));
  if(starter) {
    p.c1=CoupledRounded(p.c1+f.starter_torque_ftlb);
    p.c2=CoupledRounded(p.c2-CoupledRounded(f.starter_torque_ftlb/f.starter_limit_w_radps));
  }
  for(double c:{p.c0,p.c1,p.c2,p.c3}) CoupledOperand(c);
  if(p.c0>0.0 || p.c3>0.0) ShaftReject("coupled shaft: nonconcave source domain");
  return p;
}

CoupledShaftResultV1 CoupledMidpointStep(const CoupledShaftFrameV1& f,double w,double inertia,double rho,double diameter,double velocity) {
  ShaftEnvironment();
  for(double x:{f.pre_step_engine_rpm,f.h_s,f.engine_c0_ftlb_per_s,f.engine_c1_ftlb,f.engine_c2_ftlb_s,f.starter_torque_ftlb,f.starter_limit_w_radps,w,inertia,rho,diameter,velocity})
    if(!std::isfinite(x)) ShaftReject("coupled shaft: nonfinite frame");
  if(w<0.0 || f.pre_step_engine_rpm<0.0 || f.h_s<0.0 || inertia<=0.0 || rho<0.0 || diameter<=0.0 || f.engine_c0_ftlb_per_s>0.0 || f.starter_torque_ftlb<0.0 || f.starter_limit_w_radps<=0.0)
    ShaftReject("coupled shaft: invalid frame domain");
  if(f.mode!=ShaftOperatingModeV1::cranking && f.mode!=ShaftOperatingModeV1::running && f.mode!=ShaftOperatingModeV1::stopped)
    ShaftReject("coupled shaft: unknown operating mode");
  if((f.mode==ShaftOperatingModeV1::cranking &&
      (f.engine_c0_ftlb_per_s!=0.0 || f.engine_c2_ftlb_s!=0.0)) ||
     (f.mode==ShaftOperatingModeV1::stopped && f.engine_c2_ftlb_s!=0.0))
    ShaftReject("coupled shaft: inconsistent mode coefficients");
  CoupledShaftResultV1 out{w,true,false,0,0};
  if(f.h_s==0.0) return out;
  for(double x:{f.pre_step_engine_rpm,f.h_s,f.engine_c0_ftlb_per_s,f.engine_c1_ftlb,f.engine_c2_ftlb_s,f.starter_torque_ftlb,f.starter_limit_w_radps,w,inertia,rho,diameter,velocity}) CoupledOperand(x);
  const double twoPi=CoupledRounded(2.0*M_PI);
  const double d2=CoupledRounded(diameter*diameter),d4=CoupledRounded(d2*d2),d5=CoupledRounded(d4*diameter);
  const double k2=CoupledRounded(twoPi*twoPi),k3=CoupledRounded(k2*twoPi);
  const double L=CoupledRounded(CoupledRounded(rho*d5)/k3);
  const double A=velocity>0.0?CoupledRounded(CoupledRounded(twoPi*velocity)/diameter):0.0;
  const double cpKnot=CoupledRounded(A*0.5);
  CoupledRatio remaining(CoupledDyadic(f.h_s),CoupledDyadic(1.0));
  bool crossedCP=false,crossedStarter=false;
  for(unsigned segment=0;segment<4;++segment) {
    // At a knot either polynomial's exact predicate must agree on drift.
    CoupledLaw p=CBuildLaw(f,w,cpKnot,L,A,1);
    int drift=CEval(CTorquePolynomial(p),CoupledDyadic(w)).sign;
    if((A>0.0 && w==cpKnot) ||
       (f.mode==ShaftOperatingModeV1::cranking && w==f.starter_limit_w_radps)) {
      const CoupledLaw other=CBuildLaw(f,w,cpKnot,L,A,-1);
      const int otherDrift=CEval(CTorquePolynomial(other),CoupledDyadic(w)).sign;
      if(otherDrift!=drift) ShaftReject("coupled shaft: uncertain knot drift/equilibrium");
      // Each join is algebraically continuous before <=12 rounded coefficient
      // operations. The conservative 32u/(1-32u) enclosure is checked exactly.
      CoupledDyadic difference,magnitude,power(1.0);
      const double a[4]={p.c0,p.c1,p.c2,p.c3};
      const double b[4]={other.c0,other.c1,other.c2,other.c3};
      for(unsigned i=0;i<4;++i) {
        difference=CAdd(difference,CMul(CSub(CoupledDyadic(a[i]),CoupledDyadic(b[i])),power));
        magnitude=CAdd(magnitude,CMul(CAdd(CoupledDyadic(std::abs(a[i])),CoupledDyadic(std::abs(b[i]))),power));
        power=CMul(power,CoupledDyadic(w));
      }
      if(difference.sign<0) difference=CNeg(difference);
      const CoupledDyadic unit=CoupledDyadic(std::ldexp(1.0,-53));
      const CoupledDyadic gu=CScale(unit,5);
      if(CCompare(CMul(difference,CSub(CoupledDyadic(1.0),gu)),CMul(magnitude,gu))>0)
        ShaftReject("coupled shaft: coefficient knot enclosure");
      if(drift<0) p=other;
    }
    if(w==0.0 && (f.mode!=ShaftOperatingModeV1::cranking || drift<=0)) return out;
    if(!drift) return out;
    bool cpEvent=false,starterEvent=false,hasEndpoint=false;
    double endpoint=0.0;
    const auto consider=[&](double knot,bool cp) {
      if((drift>0 && knot>w)||(drift<0 && knot<w)) {
        if(!hasEndpoint || (drift>0?knot<endpoint:knot>endpoint)) {
          endpoint=knot;hasEndpoint=true;cpEvent=cp;starterEvent=!cp;
        } else if(knot==endpoint) {cpEvent=cpEvent||cp;starterEvent=starterEvent||!cp;}
      }
    };
    if(A>0.0 && !crossedCP) consider(cpKnot,true);
    if(f.mode==ShaftOperatingModeV1::cranking && !crossedStarter) consider(f.starter_limit_w_radps,false);
    const CoupledAdvance advanced=CAdvanceSegment(p,inertia,w,remaining,hasEndpoint,endpoint);
    out.final_w_radps=advanced.w;out.hold=out.hold && advanced.hold;
    out.reached_stop=advanced.stop;
    if(!advanced.source_event) return out;
    if(cpEvent) {if(crossedCP) ShaftReject("coupled shaft: repeated CP event");crossedCP=true;++out.cp_crossings;}
    if(starterEvent) {if(crossedStarter) ShaftReject("coupled shaft: repeated starter event");crossedStarter=true;++out.starter_taper_crossings;}
    remaining=advanced.remaining;
    if(remaining.n.sign<0) ShaftReject("coupled shaft: negative remaining time");
    w=advanced.w;out.final_w_radps=w;out.hold=false;
    if(!remaining.n.sign) return out;
  }
  ShaftReject("coupled shaft: four event segments exhausted");return out;
}

} // anonymous namespace


/*%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
CLASS IMPLEMENTATION
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%*/

FGPropeller::FGPropeller(FGFDMExec* exec, Element* prop_element, int num)
                       : FGThruster(exec, prop_element, num)
{
  Element *table_element, *local_element;
  string name="";
  auto PropertyManager = exec->GetPropertyManager();

  MaxPitch = MinPitch = P_Factor = Pitch = Advance = MinRPM = MaxRPM = 0.0;
  Sense = 1; // default clockwise rotation
  ReversePitch = 0.0;
  Reversed = false;
  Feathered = false;
  Reverse_coef = 0.0;
  GearRatio = 1.0;
  CtFactor = CpFactor = 1.0;
  ConstantSpeed = 0;
  cThrust = cPower = CtMach = CpMach = 0;
  Vinduced = 0.0;

  if (prop_element->FindElement("ixx"))
    Ixx = max(prop_element->FindElementValueAsNumberConvertTo("ixx", "SLUG*FT2"), 1e-06);

  Sense_multiplier = 1.0;
  if (prop_element->HasAttribute("version")
      && prop_element->GetAttributeValueAsNumber("version") > 1.0)
      Sense_multiplier = -1.0;

  if (prop_element->FindElement("diameter"))
    Diameter = max(prop_element->FindElementValueAsNumberConvertTo("diameter", "FT"), 0.001);
  if (prop_element->FindElement("numblades"))
    numBlades = (int)prop_element->FindElementValueAsNumber("numblades");
  if (prop_element->FindElement("gearratio"))
    GearRatio = max(prop_element->FindElementValueAsNumber("gearratio"), 0.001);
  if (prop_element->FindElement("minpitch"))
    MinPitch = prop_element->FindElementValueAsNumber("minpitch");
  if (prop_element->FindElement("maxpitch"))
    MaxPitch = prop_element->FindElementValueAsNumber("maxpitch");
  if (prop_element->FindElement("minrpm"))
    MinRPM = prop_element->FindElementValueAsNumber("minrpm");
  if (prop_element->FindElement("maxrpm")) {
    MaxRPM = prop_element->FindElementValueAsNumber("maxrpm");
    ConstantSpeed = 1;
    }
  if (prop_element->FindElement("constspeed"))
    ConstantSpeed = (int)prop_element->FindElementValueAsNumber("constspeed");
  if (prop_element->FindElement("reversepitch"))
    ReversePitch = prop_element->FindElementValueAsNumber("reversepitch");
  while((table_element = prop_element->FindNextElement("table")) != 0) {
    name = table_element->GetAttributeValue("name");
    try {
      if (name == "C_THRUST") {
        cThrust = new FGTable(PropertyManager, table_element);
      } else if (name == "C_POWER") {
        cPower = new FGTable(PropertyManager, table_element);
      } else if (name == "CT_MACH") {
        CtMach = new FGTable(PropertyManager, table_element);
      } else if (name == "CP_MACH") {
        CpMach = new FGTable(PropertyManager, table_element);
      } else {
        FGXMLLogging log(table_element, LogLevel::ERROR);
        log << "Unknown table type: " << name << " in propeller definition.\n";
      }
    } catch (BaseException& e) {
      XMLLogException err(table_element);
      err << "Error loading propeller table:" << name << ". " << e.what() << "\n";
      throw err;
    }
  }
  if( (cPower == nullptr) || (cThrust == nullptr)){
    XMLLogException err(prop_element);
    err << "Propeller configuration must contain C_THRUST and C_POWER tables!\n";
    throw err;
  }

  local_element = prop_element->GetParent()->FindElement("sense");
  if (local_element) {
    double Sense = local_element->GetDataAsNumber();
    SetSense(Sense >= 0.0 ? 1.0 : -1.0);
  }
  local_element = prop_element->GetParent()->FindElement("p_factor");
  if (local_element) {
    P_Factor = local_element->GetDataAsNumber();
  }
  if (P_Factor < 0) {
    XMLLogException err(local_element);
    err << "P-Factor value in propeller configuration file must be greater than zero\n";
    throw err;
  }
  if (prop_element->FindElement("ct_factor"))
    SetCtFactor( prop_element->FindElementValueAsNumber("ct_factor") );
  if (prop_element->FindElement("cp_factor"))
    SetCpFactor( prop_element->FindElementValueAsNumber("cp_factor") );

  Type = ttPropeller;
  RPM = 0;
  vTorque.InitMatrix();
  D4 = Diameter*Diameter*Diameter*Diameter;
  D5 = D4*Diameter;
  Pitch = MinPitch;

  string property_name, base_property_name;
  base_property_name = CreateIndexedPropertyName("propulsion/engine", EngineNum);
  property_name = base_property_name + "/engine-rpm";
  PropertyManager->Tie( property_name.c_str(), this, &FGPropeller::GetEngineRPM );
  property_name = base_property_name + "/advance-ratio";
  PropertyManager->Tie( property_name.c_str(), &J );
  property_name = base_property_name + "/blade-angle";
  PropertyManager->Tie( property_name.c_str(), &Pitch );
  property_name = base_property_name + "/thrust-coefficient";
  PropertyManager->Tie( property_name.c_str(), this, &FGPropeller::GetThrustCoefficient );
  property_name = base_property_name + "/propeller-rpm";
  PropertyManager->Tie( property_name.c_str(), this, &FGPropeller::GetRPM );
  property_name = base_property_name + "/helical-tip-Mach";
  PropertyManager->Tie( property_name.c_str(), this, &FGPropeller::GetHelicalTipMach );
  property_name = base_property_name + "/constant-speed-mode";
  PropertyManager->Tie( property_name.c_str(), this, &FGPropeller::GetConstantSpeed,
                      &FGPropeller::SetConstantSpeed );
  property_name = base_property_name + "/prop-induced-velocity_fps"; // [ft/sec]
  PropertyManager->Tie( property_name.c_str(), this, &FGPropeller::GetInducedVelocity,
                      &FGPropeller::SetInducedVelocity );
  property_name = base_property_name + "/propeller-power-ftlbps"; // [ft-lbs/sec]
  PropertyManager->Tie( property_name.c_str(), &PowerRequired );
  property_name = base_property_name + "/propeller-torque-ftlb"; // [ft-lbs]
  PropertyManager->Tie( property_name.c_str(), this, &FGPropeller::GetTorque);
  property_name = base_property_name + "/propeller-sense";
  PropertyManager->Tie( property_name.c_str(), &Sense );

  Debug(0);
}

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

FGPropeller::~FGPropeller()
{
  delete cThrust;
  delete cPower;
  delete CtMach;
  delete CpMach;

  Debug(1);
}

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

void FGPropeller::ResetToIC(void)
{
  FGThruster::ResetToIC();
  Vinduced = 0.0;
}

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
//
// We must be getting the aerodynamic velocity here, NOT the inertial velocity.
// We need the velocity with respect to the wind.
//
// Remembering that Torque * omega = Power, we can derive the torque on the
// propeller and its acceleration to give a new RPM. The current RPM will be
// used to calculate thrust.
//
// Because RPM could be zero, we need to be creative about what RPM is stated as.

// ADR015: actual loaded source topology query, not a model-name assertion.
bool FGPropeller::SupportsCoupledShaftProfileV1() const
{
  if(GearRatio!=1.0 || Ixx!=2.0 || Diameter!=6.0 || numBlades!=2 ||
     MinPitch!=20.0 || MaxPitch!=20.0 || Pitch!=20.0 ||
     ConstantSpeed!=0 || CtFactor!=1.0 || CpFactor!=1.0 ||
     CtMach || CpMach || Reversed || Feathered || Reverse_coef!=0.0 ||
     !cPower || !cThrust || cPower->GetNumRows()!=4 || cThrust->GetNumRows()!=4)
    return false;
  const double axis[4]={-1.0,0.0,1.0,2.0};
  const double cp[4]={0.06,0.06,0.04,0.02};
  const double ct[4]={0.12,0.12,0.0,-0.06};
  for(unsigned i=0;i<4;++i)
    if(cPower->GetElement(i+1,0)!=axis[i] || cPower->GetElement(i+1,1)!=cp[i] ||
       cThrust->GetElement(i+1,0)!=axis[i] || cThrust->GetElement(i+1,1)!=ct[i]) return false;
  return true;
}

double FGPropeller::Calculate(double EnginePower)
{
  if(angularIntegrationMethod==AngularIntegrationMethod::event_aware_coupled_midpoint_v1)
    ShaftReject("coupled shaft: scalar Calculate has no owned piston frame");
  return CalculateWithFrame(EnginePower,nullptr);
}

double FGPropeller::CalculateCoupled(const CoupledShaftFrameV1& frame,double reaction_power)
{
  ShaftEnvironment();
  if(angularIntegrationMethod!=AngularIntegrationMethod::event_aware_coupled_midpoint_v1 ||
     !SupportsCoupledShaftProfileV1() || frame.pre_step_engine_rpm!=GetEngineRPM() ||
     frame.h_s!=in.TotalDeltaT || !std::isfinite(reaction_power))
    ShaftReject("coupled shaft: unsupported method, topology or stale frame");
  return CalculateWithFrame(reaction_power,&frame);
}

double FGPropeller::CalculateWithFrame(double EnginePower, const CoupledShaftFrameV1* frame)
{
  FGColumnVector3 vDXYZ = MassBalance->StructuralToBody(vXYZn);
  const FGMatrix33& mT = Transform();
  // Local air velocity is obtained from Stevens & Lewis' "Aircraft Control and
  // Simualtion (3rd edition)" eqn 8.2-1
  // Variables in.AeroUVW and in.AeroPQR include the wind and turbulence effects
  // as computed by FGAuxiliary.
  FGColumnVector3 localAeroVel = mT.Transposed() * (in.AeroUVW + in.AeroPQR*vDXYZ);
  double omega, PowerAvailable;

  double Vel = localAeroVel(eU);
  double rho = in.Density;
  double RPS = RPM/60.0;

  // Calculate helical tip Mach
  double Area = 0.25*Diameter*Diameter*M_PI;
  double Vtip = RPS * Diameter * M_PI;
  HelicalTipMach = sqrt(Vtip*Vtip + Vel*Vel) / in.Soundspeed;

  if (RPS > 0.01) J = Vel / (Diameter * RPS); // Calculate J normally
  else           J = Vel / Diameter;

  PowerAvailable = EnginePower - GetPowerRequired();

  if (MaxPitch == MinPitch) {    // Fixed pitch prop
    ThrustCoeff = cThrust->GetValue(J);
  } else {                       // Variable pitch prop
    ThrustCoeff = cThrust->GetValue(J, Pitch);
  }

  // Apply optional scaling factor to Ct (default value = 1)
  ThrustCoeff *= CtFactor;

  // Apply optional Mach effects from CT_MACH table
  if (CtMach) ThrustCoeff *= CtMach->GetValue(HelicalTipMach);

  Thrust = ThrustCoeff*RPS*RPS*D4*rho;

  // Induced velocity in the propeller disk area. This formula is obtained
  // from momentum theory - see B. W. McCormick, "Aerodynamics, Aeronautics,
  // and Flight Mechanics" 1st edition, eqn. 6.15 (propeller analysis chapter).
  // Since Thrust and Vel can both be negative we need to adjust this formula
  // To handle sign (direction) separately from magnitude.
  double Vel2sum = Vel*abs(Vel) + 2.0*Thrust/(rho*Area);

  if( Vel2sum > 0.0)
    Vinduced = 0.5 * (-Vel + sqrt(Vel2sum));
  else
    Vinduced = 0.5 * (-Vel - sqrt(-Vel2sum));

  // P-factor is simulated by a shift of the acting location of the thrust.
  // The shift is a multiple of the angle between the propeller shaft axis
  // and the relative wind that goes through the propeller disk.
  if (P_Factor > 0.0001) {
    double tangentialVel = localAeroVel.Magnitude(eV, eW);

    if (tangentialVel > 0.0001) {
      // The angle made locally by the air flow with respect to the propeller
      // axis is influenced by the induced velocity. This attenuates the
      // influence of a string cross wind and gives a more realistic behavior.
      double angle = atan2(tangentialVel, Vel+Vinduced);
      double factor = Sense * P_Factor * angle / tangentialVel;
      SetActingLocationY( GetLocationY() + factor * localAeroVel(eW));
      SetActingLocationZ( GetLocationZ() + factor * localAeroVel(eV));
    }
  }

  omega = RPS*2.0*M_PI;

  vFn(eX) = Thrust;
  vTorque(eX) = -Sense*EnginePower / max(0.01, omega);

  // The Ixx value and rotation speed given below are for rotation about the
  // natural axis of the engine. The transform takes place in the base class
  // FGForce::GetBodyForces() function.

  FGColumnVector3 vH(Ixx*omega*Sense*Sense_multiplier, 0.0, 0.0);

  if (angularIntegrationMethod == AngularIntegrationMethod::legacy_euler) {
    if (omega > 0.01) ExcessTorque = PowerAvailable / omega;
    else             ExcessTorque = PowerAvailable / 1.0;

    RPM = (RPS + ((ExcessTorque / Ixx) / (2.0 * M_PI)) * in.TotalDeltaT) * 60.0;

    if (RPM < 0.0) RPM = 0.0; // Engine won't turn backwards
  } else if (angularIntegrationMethod == AngularIntegrationMethod::event_aware_constant_power_v1) {
    // Project modification 2026-10-09: opt-in held-power angular update only.
    // Engine/load/thrust/reaction torque/momentum chronology above is unchanged.
    ShaftEnvironment();
    if (!std::isfinite(RPM) || RPM < 0.0 || !std::isfinite(EnginePower) ||
        !std::isfinite(PowerRequired) || !std::isfinite(PowerAvailable) ||
        !std::isfinite(omega) || omega < 0.0 || !std::isfinite(Ixx) || Ixx <= 0.0 ||
        !std::isfinite(in.TotalDeltaT) || in.TotalDeltaT < 0.0)
      ShaftReject("event-aware shaft: invalid RPM, power, inertia, interval or omega");
    if (in.TotalDeltaT != 0.0 && PowerAvailable != 0.0) {
      // Holds preserve even finite subnormal original RPM. Progress requires the
      // original RPM and existing source conversion to stay in the audited domain.
      ShaftOperand(RPM);
      ShaftFiniteNormalOrZero(RPS);
      ShaftFiniteNormalOrZero(omega);
      if (RPM > 0.0 && (RPS == 0.0 || omega == 0.0))
        ShaftReject("event-aware shaft: positive RPM conversion lost");
    }
    const ShaftDecision candidate = ShaftEventStep(omega, PowerAvailable, Ixx, in.TotalDeltaT);
    if (!candidate.hold) {
      // Stop is literal positive zero. Holds never enter this conversion/assignment.
      const double candidateRPM = candidate.omega == 0.0 ? 0.0
                                  : (candidate.omega / (2.0 * M_PI)) * 60.0;
      ShaftFiniteNormalOrZero(candidateRPM);
      if (candidateRPM < 0.0 || (candidate.omega > 0.0 && candidateRPM == 0.0))
        ShaftReject("event-aware shaft: invalid RPM conversion");
      RPM = candidateRPM;
    }
  } else if (angularIntegrationMethod == AngularIntegrationMethod::event_aware_coupled_midpoint_v1) {
    if(!frame || !std::isfinite(RPM) || RPM<0.0 || !std::isfinite(omega) || omega<0.0 ||
       !std::isfinite(rho) || rho<=0.0)
      ShaftReject("coupled shaft: invalid actual propeller state");
    const CoupledShaftResultV1 candidate=CoupledMidpointStep(*frame,omega,Ixx,rho,Diameter,Vel);
    if(!candidate.hold) {
      const double candidateRPM=candidate.final_w_radps==0.0?0.0
          : CoupledRounded(CoupledRounded(candidate.final_w_radps/(2.0*M_PI))*60.0);
      if(candidateRPM<0.0 || (candidate.final_w_radps>0.0 && candidateRPM==0.0))
        ShaftReject("coupled shaft: invalid final RPM conversion");
      RPM=candidateRPM;
    }
  } else {
    ShaftReject("event-aware shaft: unknown angular method");
  }

  // Transform Torque and momentum first, as PQR is used in this
  // equation and cannot be transformed itself.
  vMn = in.PQRi*(mT*vH) + mT*vTorque;

  return Thrust; // return thrust in pounds
}

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

double FGPropeller::GetPowerRequired(void)
{
  double cPReq;

  if (MaxPitch == MinPitch) {   // Fixed pitch prop
    cPReq = cPower->GetValue(J);

  } else {                      // Variable pitch prop

    if (ConstantSpeed != 0) {   // Constant Speed Mode

      // do normal calculation when propeller is neither feathered nor reversed
      // Note:  This method of feathering and reversing was added to support the
      //        turboprop model.  It's left here for backward compatiblity, but
      //        now feathering and reversing should be done in Manual Pitch Mode.
      if (!Feathered) {
        if (!Reversed) {

          double rpmReq = MinRPM + (MaxRPM - MinRPM) * Advance;
          double dRPM = rpmReq - RPM;
          // The pitch of a variable propeller cannot be changed when the RPMs are
          // too low - the oil pump does not work.
          if (RPM > 200) Pitch -= dRPM * in.TotalDeltaT;
          if (Pitch < MinPitch)       Pitch = MinPitch;
          else if (Pitch > MaxPitch)  Pitch = MaxPitch;

        } else { // Reversed propeller

          // when reversed calculate propeller pitch depending on throttle lever position
          // (beta range for taxing full reverse for braking)
          double PitchReq = MinPitch - ( MinPitch - ReversePitch ) * Reverse_coef;
          // The pitch of a variable propeller cannot be changed when the RPMs are
          // too low - the oil pump does not work.
          if (RPM > 200) Pitch += (PitchReq - Pitch) / 200;
          if (RPM > MaxRPM) {
            Pitch += (MaxRPM - RPM) / 50;
            if (Pitch < ReversePitch) Pitch = ReversePitch;
            else if (Pitch > MaxPitch)  Pitch = MaxPitch;
          }
        }

      } else { // Feathered propeller
               // ToDo: Make feathered and reverse settings done via FGKinemat
        Pitch += (MaxPitch - Pitch) / 300; // just a guess (about 5 sec to fully feathered)
      }

    } else { // Manual Pitch Mode, pitch is controlled externally

    }

    cPReq = cPower->GetValue(J, Pitch);
  }

  // Apply optional scaling factor to Cp (default value = 1)
  cPReq *= CpFactor;

  // Apply optional Mach effects from CP_MACH table
  if (CpMach) cPReq *= CpMach->GetValue(HelicalTipMach);

  double RPS = RPM / 60.0;
  double local_RPS = RPS < 0.01 ? 0.01 : RPS;

  PowerRequired = cPReq*local_RPS*local_RPS*local_RPS*D5*in.Density;

  return PowerRequired;
}

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

FGColumnVector3 FGPropeller::GetPFactor() const
{
  // These are moments in lbf per ft : the lever arm along Z generates a moment
  // along the pitch direction.
  double p_pitch = Thrust * Sense * (GetActingLocationZ() - GetLocationZ()) / 12.0;
  // The lever arm along Y generates a moment along the yaw direction.
  double p_yaw = Thrust * Sense * (GetActingLocationY() - GetLocationY()) / 12.0;

  return FGColumnVector3(0.0, p_pitch, p_yaw);
}

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

string FGPropeller::GetThrusterLabels(int id, const string& delimeter)
{
  std::ostringstream buf;

  buf << Name << " Torque (engine " << id << ")" << delimeter
      << Name << " PFactor Pitch (engine " << id << ")" << delimeter
      << Name << " PFactor Yaw (engine " << id << ")" << delimeter
      << Name << " Thrust (engine " << id << " in lbs)" << delimeter;
  if (IsVPitch())
    buf << Name << " Pitch (engine " << id << ")" << delimeter;
  buf << Name << " RPM (engine " << id << ")";

  return buf.str();
}

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

string FGPropeller::GetThrusterValues(int id, const string& delimeter)
{
  std::ostringstream buf;

  FGColumnVector3 vPFactor = GetPFactor();
  buf << vTorque(eX) << delimeter
      << vPFactor(ePitch) << delimeter
      << vPFactor(eYaw) << delimeter
      << Thrust << delimeter;
  if (IsVPitch())
    buf << Pitch << delimeter;
  buf << RPM;

  return buf.str();
}

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
//    The bitmasked value choices are as follows:
//    unset: In this case (the default) JSBSim would only print
//       out the normally expected messages, essentially echoing
//       the config files as they are read. If the environment
//       variable is not set, debug_lvl is set to 1 internally
//    0: This requests JSBSim not to output any messages
//       whatsoever.
//    1: This value explicity requests the normal JSBSim
//       startup messages
//    2: This value asks for a message to be printed out when
//       a class is instantiated
//    4: When this value is set, a message is displayed when a
//       FGModel object executes its Run() method
//    8: When this value is set, various runtime state variables
//       are printed out periodically
//    16: When set various parameters are sanity checked and
//       a message is printed out when they go out of bounds

void FGPropeller::Debug(int from)
{
  if (debug_lvl <= 0) return;

  if (debug_lvl & 1) { // Standard console startup message output
    if (from == 0) { // Constructor
      FGLogging log(LogLevel::DEBUG);
      log << "\n    Propeller Name: " << Name << "\n";
      log << "      IXX = " << Ixx << "\n";
      log << "      Diameter = " << Diameter << " ft." << "\n";
      log << "      Number of Blades  = " << numBlades << "\n";
      log << "      Gear Ratio  = " << GearRatio << "\n";
      log << "      Minimum Pitch  = " << MinPitch << "\n";
      log << "      Maximum Pitch  = " << MaxPitch << "\n";
      log << "      Minimum RPM  = " << MinRPM << "\n";
      log << "      Maximum RPM  = " << MaxRPM << "\n";
    }
  }
  if (debug_lvl & 2 ) { // Instantiation/Destruction notification
    FGLogging log(LogLevel::DEBUG);
    if (from == 0) log << "Instantiated: FGPropeller\n";
    if (from == 1) log << "Destroyed:    FGPropeller\n";
  }
  if (debug_lvl & 4 ) { // Run() method entry print for FGModel-derived objects
  }
  if (debug_lvl & 8 ) { // Runtime state variables
  }
  if (debug_lvl & 16) { // Sanity checking
  }
  if (debug_lvl & 64) {
    if (from == 0) { // Constructor
    }
  }
}
}
