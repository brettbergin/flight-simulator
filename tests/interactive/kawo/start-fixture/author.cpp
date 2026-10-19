#include "fixture-common.hpp"

namespace s=start_fixture;
namespace {
s::Vec linear_solve(s::Mat a,s::Vec b) {
  for(std::size_t col=0;col<3;++col) {
    std::size_t best=col;for(std::size_t row=col+1;row<3;++row)if(std::abs(a[3*row+col])>std::abs(a[3*best+col]))best=row;
    s::require(std::isfinite(a[3*best+col])&&a[3*best+col]!=0,"zero/nonfinite Newton pivot");
    if(best!=col){for(std::size_t k=0;k<3;++k)std::swap(a[3*best+k],a[3*col+k]);std::swap(b[best],b[col]);}
    for(std::size_t row=col+1;row<3;++row) {
      const double f=s::div(a[3*row+col],a[3*col+col]);a[3*row+col]=0;
      for(std::size_t k=col+1;k<3;++k)a[3*row+k]=s::sub(a[3*row+k],s::mul(f,a[3*col+k]));
      b[row]=s::sub(b[row],s::mul(f,b[col]));
    }
  }
  s::Vec result{};
  for(int i=2;i>=0;--i){const auto row=static_cast<std::size_t>(i);double v=b[row];for(std::size_t k=row+1;k<3;++k)v=s::sub(v,s::mul(a[3*row+k],result[k]));result[row]=s::div(v,a[3*row+row]);}
  s::require(s::finite(result),"nonfinite Newton update");return result;
}
}
int main(int argc,char** argv) {
  try {
    s::environment();s::require(argc==4,"usage: author ABSOLUTE_PAYLOAD ABSOLUTE_RECEIPT ABSOLUTE_ORIGINAL_MODEL_ROOT");
    s::emit_inputs();s::verify_model(argv[3]);const s::Terrain t(argv[1],argv[2]);
    s::g::Boundary seed_boundary(t.provider,{{0},"qualification.kawo-start-seed"},1);
    const auto seed_query=s::inverse(t.frame.point({t.x,0,t.z}));
    const auto seed_sample=t.sample(seed_boundary,seed_query);auto seed_contact=seed_query;seed_contact.ellipsoid_height_m=seed_sample.surface_height_m;
    const double seed_y=s::sum(t.frame.project(s::forward(seed_contact))[1],1.05);
    s::Vec unknown{seed_y,0,0};std::size_t evaluations=0;unsigned updates=0;
    const auto evaluate=[&](s::Vec value){s::require(++evaluations<=362,"author evaluation cap");return s::evaluate(t,value);};
    auto current=evaluate(unknown);
    std::cout<<"{\"event\":\"chainage\",\"x_m\":"<<t.x<<",\"z_m\":"<<t.z<<",\"seed_y_m\":"<<seed_y<<",\"goal_m\":0.05}\n";
    for(unsigned iteration=0;iteration<24 && s::maxabs(current.residual)>s::residual_limit;++iteration) {
      s::Mat jacobian{};constexpr s::Vec perturbation{0x1p-10,0x1p-16,0x1p-16};
      for(std::size_t col=0;col<3;++col){auto lo=unknown,hi=unknown;lo[col]=s::sub(lo[col],perturbation[col]);hi[col]=s::sum(hi[col],perturbation[col]);const auto l=evaluate(lo),h=evaluate(hi);for(std::size_t row=0;row<3;++row)jacobian[3*row+col]=s::div(s::sub(h.residual[row],l.residual[row]),s::mul(2,perturbation[col]));}
      const auto step=linear_solve(jacobian,s::scale(current.residual,-1));bool accepted=false;
      std::cout<<"{\"event\":\"newton\",\"iteration\":"<<iteration<<",\"before\":";s::emit_vec(std::cout,current.residual);std::cout<<",\"step\":";s::emit_vec(std::cout,step);std::cout<<"}\n";
      for(unsigned backtrack=0;backtrack<8;++backtrack){
        const double alpha=std::ldexp(1.,-static_cast<int>(backtrack));const auto next=s::plus(unknown,s::scale(step,alpha));
        if(!s::finite(next)||next[0]<-1000||next[0]>4096||std::abs(next[1])>.2||std::abs(next[2])>.2){std::cout<<"{\"event\":\"trial-domain-refusal\",\"iteration\":"<<iteration<<",\"backtrack\":"<<backtrack<<"}\n";continue;}
        const auto trial=evaluate(next);std::cout<<"{\"event\":\"trial\",\"iteration\":"<<iteration<<",\"backtrack\":"<<backtrack<<",\"residual\":";s::emit_vec(std::cout,trial.residual);std::cout<<"}\n";
        if(s::maxabs(trial.residual)<s::maxabs(current.residual)){unknown=next;current=trial;accepted=true;++updates;break;}
      }
      s::require(accepted,"Newton line search did not improve");
    }
    const auto final=evaluate(unknown);s::clearances(t,final);s::verify_model(argv[3]);
    std::cout<<"{\"event\":\"authored-pose\",\"passed\":true,\"updates\":"<<updates<<",\"residual_evaluations\":"<<evaluations<<",\"pose\":";s::emit_evaluation(std::cout,final);
    std::cout<<",\"runic_qualified\":false,\"runtime_admitted\":false}\n";
    s::require(std::cout.good(),"author output failed");return 0;
  } catch(const std::exception& error) {
    std::cout<<"{\"event\":\"author-refused\",\"passed\":false,\"reason\":"<<s::quoted(error.what())<<"}\n";std::cerr<<"author refused: "<<error.what()<<'\n';return 1;
  } catch(...) {
    std::cout<<"{\"event\":\"author-refused\",\"passed\":false,\"reason\":\"nonstandard bounded-arithmetic failure\"}\n";return 1;
  }
}
