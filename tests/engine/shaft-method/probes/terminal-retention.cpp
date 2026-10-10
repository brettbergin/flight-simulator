// Actual Session negative unit fixture. No model/property/RPM injection.
#include <flight/interactive/session.hpp>
#include <flight/fdm/protocol.hpp>
#include "loaded-library.hpp"
#include <array>
#include <bit>
#include <cfenv>
#include <cstdint>
#include <iostream>
#include <stdexcept>
#include <string>
#include <xmmintrin.h>

#if !defined(_M_X64) && !defined(__x86_64__)
#error This prospective environment-rejection fixture requires the audited x64 route.
#endif

namespace p = flight::interactive;
namespace c = flight::contracts::v1;

void require(bool condition, const char* message) {
  if (!condition) throw std::runtime_error(message);
}

template<std::size_t N>
bool same_bits(const std::array<double,N>& a, const std::array<double,N>& b) {
  for (std::size_t i=0;i<N;++i)
    if (std::bit_cast<std::uint64_t>(a[i])!=std::bit_cast<std::uint64_t>(b[i])) return false;
  return true;
}

std::array<double,8> axes_values(const c::PilotAxes& a) {
  return {a.roll,a.pitch,a.yaw,a.throttle,a.mixture,a.left_brake,a.right_brake,a.trim};
}

std::array<double,10> diagnostic_values(const p::PistonDiagnostics& d) {
  return {d.pre_prop_engine_rpm,d.post_prop_rpm,d.fuel_flow_lb_per_s,d.fuel_used_lb,
    d.manifold_pressure_inhg,d.engine_input_pressure_psf,d.engine_input_density_slug_per_ft3,
    d.raw_engine_power_ftlb_per_s,d.tank_contents_lb,d.mass_slug};
}

std::array<bool,4> switches(const c::AircraftSnapshot& s) {
  constexpr std::array<const char*,4> ids{
    "engine.ignition_left","engine.ignition_right","engine.starter","fuel.feed"};
  std::array<bool,4> result{};
  for (std::size_t i=0;i<ids.size();++i) {
    bool found=false;
    for (const auto& x:s.systems) if(x.id==ids[i]) {
      require(!found && x.quantity==c::Quantity::boolean && x.validity==c::Validity::valid,
        "Invalid/duplicate switch readback");
      result[i]=std::get<bool>(x.value);found=true;
    }
    require(found,"Missing switch readback");
  }
  return result;
}

class TowardZero final {
 public:
  TowardZero():rounding_(std::fegetround()),mxcsr_(_mm_getcsr()) {
    require(rounding_==FE_TONEAREST && (mxcsr_&(0x8000u|0x0040u|0x6000u))==0,
      "Fixture requires supported initial floating controls");
    if(std::fesetround(FE_TOWARDZERO)!=0 || std::fegetround()!=FE_TOWARDZERO) {
      restore();throw std::runtime_error("Cannot establish toward-zero fixture control");
    }
  }
  ~TowardZero() noexcept {restore();}
  TowardZero(const TowardZero&)=delete;
  TowardZero& operator=(const TowardZero&)=delete;
 private:
  void restore() noexcept {
    (void)std::fesetround(rounding_);
    _mm_setcsr(mxcsr_); // Restore rounding, FTZ/DAZ and original sticky bits.
  }
  int rounding_;
  unsigned mxcsr_;
};

int main(int argc,char** argv) {
  std::string loaded_library;
  try {
    require(argc==2,"Usage: coupled_terminal_retention model_root");
    loaded_library=piston_fixture::loaded_library_path();
    p::SurfaceConfig surface_config;
    auto world=std::make_shared<const p::AnalyticSurface>(surface_config,p::prepared_identity(surface_config));
    p::Config config;
    config.profile=p::Profile::piston;
    config.angular_method=p::AngularMethod::event_aware_coupled_midpoint_v1;
    config.start=p::Start::piston_cold_ground;
    config.model_root=argv[1];config.surface=world;
    config.session_id="coupled-terminal-retention-unit";
    p::Session session(config);
    require(session.angular_integration_method()==std::optional<std::string>{"event_aware_coupled_midpoint_v1"},
      "Actual initialized method mismatch");
    require(session.step_fixed().status==p::Status::completed,"Initial supported tick failed");
    const auto snapshot=session.latest();
    require(snapshot.header.tick.value==1,"Fixture did not complete exactly one tick");
    const auto before_snapshot=p::snapshot_json(snapshot);
    const auto before_weather=flight::fdm::transport::json(session.atmosphere());
    const auto before_axes=session.held();
    const auto before_switches=switches(snapshot);
    const auto before_diagnostic=session.piston_diagnostics();
    const auto next=c::Tick{snapshot.header.tick.value+1};
    auto candidate_axes=before_axes;candidate_axes.mixture=1;
    require(session.submit({{next,config.session_id},{1},"pilot.controls",c::Authority::pilot,
      {"unassisted",{}},candidate_axes})==c::CommandRejection::none,"Mixture command rejected");
    require(session.submit({{next,config.session_id},{2},"pilot.controls",c::Authority::pilot,
      {"unassisted",{}},c::SystemControl{"engine.starter",true}})==c::CommandRejection::none,
      "Starter command rejected");
    require(before_axes.mixture==0 && !before_switches[2],"Candidate controls do not differ from completed controls");

    const int before_rounding=std::fegetround();
    const unsigned before_mxcsr=_mm_getcsr();
    p::Step rejected;
    { TowardZero unsupported_environment; rejected=session.step_fixed(); }
    require(std::fegetround()==before_rounding && _mm_getcsr()==before_mxcsr,
      "Fixture did not restore exact FE/MXCSR controls");
    require(rejected.status==p::Status::discarded && rejected.applied.empty() && !session.live(),
      "Unsupported actual engine environment did not discard executive");
    require(session.fault()=="coupled piston: rounding mode unsupported","Wrong actual coupled-piston rejection");
    const auto retained=[&] {
      require(p::snapshot_json(session.latest())==before_snapshot,"Failure changed completed snapshot");
      require(flight::fdm::transport::json(session.atmosphere())==before_weather,"Failure changed completed weather");
      require(same_bits(axes_values(session.held()),axes_values(before_axes)),"Failure committed candidate axes");
      require(switches(session.latest())==before_switches,"Failure committed candidate switches");
      const auto d=session.piston_diagnostics();
      require(d.header.tick==before_diagnostic.header.tick && d.header.session_id==before_diagnostic.header.session_id &&
        same_bits(diagnostic_values(d),diagnostic_values(before_diagnostic)),"Failure changed completed diagnostics");
    };
    retained();
    require(session.step_fixed().status==p::Status::discarded && !session.live(),"Discarded executive resumed");
    retained();session.close();retained();
    require(piston_fixture::loaded_library_path()==loaded_library,"Loaded DLL identity changed");
    std::cout<<"{\"passed\":true,\"scope\":\"actual coupled Session terminal-retention negative unit; not physical lifecycle\","
      <<"\"completed_tick\":1,\"failure\":\"coupled piston: rounding mode unsupported\","
      <<"\"candidate_controls_uncommitted\":true,\"fe_mxcsr_restored\":true,\"loaded_library_path\":"
      <<piston_fixture::json_path(loaded_library)<<",\"source_fingerprint\":\""<<p::source_fingerprint()<<"\"}\n";
    return 0;
  } catch(const std::exception& e) {
    std::cerr<<e.what()<<'\n';
    std::cout<<"{\"passed\":false,\"loaded_library_path\":"<<piston_fixture::json_path(loaded_library)<<"}\n";
    return 1;
  }
}
