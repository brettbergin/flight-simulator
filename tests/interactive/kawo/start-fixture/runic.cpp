#include <FGFDMExec.h>
#include <initialization/FGInitialCondition.h>
#include <input_output/FGGroundCallback.h>
#include <models/FGFCS.h>
#include <models/FGGroundReactions.h>
#include <models/FGInertial.h>
#include <models/FGMassBalance.h>
#include <models/FGPropagate.h>
#include <models/FGPropulsion.h>
#include <models/FGAtmosphere.h>
#include <models/atmosphere/FGWinds.h>
#include <models/propulsion/FGTank.h>
#include "fixture-common.hpp"
#ifndef START_REFERENCE_HEADER
#error Independently reviewed pre-RunIC pose reference header required
#endif
#include START_REFERENCE_HEADER

namespace s=start_fixture;
namespace j=JSBSim;
namespace r=kawo_start_reference;
namespace {
s::c::GeodeticPosition geodetic(const j::FGLocation& input) {
  auto p=input;p.SetEllipse(s::c::geodesy::semi_major_m/s::feet,s::c::geodesy::semi_minor_m/s::feet);
  return {p.GetGeodLatitudeRad(),p.GetLongitude(),p.GetGeodAltitude()*s::feet};
}
s::Vec actual_ecef(const j::FGLocation& p) {return {p(1)*s::feet,p(2)*s::feet,p(3)*s::feet};}
s::Vec column(const j::FGColumnVector3& p,double factor=1) {return {p(1)*factor,p(2)*factor,p(3)*factor};}
void check_near(s::Vec actual,s::Vec expected,double limit,const char* why) {
  s::require(s::finite(actual)&&s::finite(expected),"nonfinite correspondence");
  for(std::size_t i=0;i<3;++i)s::require(std::abs(s::sub(actual[i],expected[i]))<=limit,why);
}
void loaded_library() {
#ifdef _WIN32
  struct Symbol:j::FGJSBBase {using FGJSBBase::CreateIndexedPropertyName;};
  const void* address=reinterpret_cast<const void*>(&Symbol::CreateIndexedPropertyName);HMODULE handle=nullptr;
  s::require(GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS|GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,reinterpret_cast<LPCWSTR>(address),&handle)!=0,"loaded JSBSim module unavailable");
  std::vector<wchar_t> name(32768);const auto count=GetModuleFileNameW(handle,name.data(),static_cast<DWORD>(name.size()));
  s::require(count>0&&count<name.size(),"loaded JSBSim path unavailable");const auto path=s::ordinary(std::filesystem::path(std::wstring(name.data(),count)),false);
  const auto u8=path.generic_u8string();
  std::cout<<"{\"event\":\"loaded-native\",\"path\":"<<s::quoted(std::string(u8.begin(),u8.end()))<<",\"version\":"<<s::quoted(j::FGJSBBase::GetVersion())<<",\"hash_authority\":\"mandatory-outer-Root-path-byte-seal\"}\n";
#else
  throw std::runtime_error("this private actual RunIC probe is Windows x64 only");
#endif
}
struct Observation {
  s::Vec cg_ecef,cg_eus,uvw,pqr; s::c::GeodeticPosition cg; s::Mat matrix;
  double time{},fuel{};s::Vec wind;bool running{};
};
struct Callback final:j::FGGroundCallback {
  const s::Terrain& terrain;s::g::Boundary boundary;bool disposing=false;std::string phase="IC-setters";
  explicit Callback(const s::Terrain& t):terrain(t),boundary(t.provider,{{0},"qualification.kawo-start-runic"},4096){}
  double GetAGLevel(double query_time,const j::FGLocation& query,j::FGLocation& contact,j::FGColumnVector3& normal,j::FGColumnVector3& velocity,j::FGColumnVector3& angular) const override {
    // Terminal Unbind getter edge only; no RunIC/publication can use these values.
    if(disposing){contact=query;normal={0,0,0};velocity={0,0,0};angular={0,0,0};return 0;}
    auto& owner=const_cast<Callback&>(*this);
    const auto pos=geodetic(query);const auto local=terrain.frame.project(s::forward(pos));
    s::require(std::isfinite(query_time)&&query_time==0,"callback advanced sim time");
    s::require(local[0]>=s::sub(terrain.x,8)&&local[0]<=s::sum(terrain.x,8)&&local[2]>=s::sub(terrain.z,8)&&local[2]<=s::sum(terrain.z,8),"callback outside private8m rectangle");
    const auto ground=terrain.sample(owner.boundary,pos);const s::Local basis(pos);
    const auto n=basis.offset({ground.normal_ned.x,ground.normal_ned.y,ground.normal_ned.z});
    contact=query;contact.SetEllipse(s::c::geodesy::semi_major_m/s::feet,s::c::geodesy::semi_minor_m/s::feet);
    contact.SetPositionGeodetic(pos.longitude_rad,pos.latitude_rad,ground.surface_height_m/s::feet);
    normal={n[0],n[1],n[2]};velocity={0,0,0};angular={0,0,0};
    std::cout<<"{\"event\":\"callback\",\"phase\":"<<s::quoted(phase)<<",\"index\":"<<owner.boundary.query_count()<<",\"geodetic\":";s::emit_vec(std::cout,s::geod_vec(pos));
    std::cout<<",\"surface_height_word\":"<<s::quoted(s::word(ground.surface_height_m))<<",\"normal_ned\":";s::emit_vec(std::cout,{ground.normal_ned.x,ground.normal_ned.y,ground.normal_ned.z});
    std::cout<<",\"material\":"<<s::quoted(ground.material_id)<<"}\n";
    return (pos.ellipsoid_height_m-ground.surface_height_m)/s::feet;
  }
};
struct Deleter {
  Callback** callback;
  void operator()(j::FGFDMExec* p) const noexcept {if(p){if(*callback)(*callback)->disposing=true;delete p;*callback=nullptr;}}
};
Observation observe(j::FGFDMExec& exec,const s::Terrain& terrain,std::string_view phase) {
  const auto prop=exec.GetPropagate();Observation o{};o.cg=geodetic(prop->GetLocation());o.cg_ecef=actual_ecef(prop->GetLocation());o.cg_eus=terrain.frame.project(o.cg_ecef);
  o.uvw=column(prop->GetUVW(),s::feet);o.pqr=column(prop->GetPQR());const auto& matrix=prop->GetTb2l();
  for(std::size_t i=0;i<3;++i)for(std::size_t k=0;k<3;++k)o.matrix[3*i+k]=matrix(static_cast<int>(i+1),static_cast<int>(k+1));
  o.time=exec.GetSimTime();o.fuel=exec.GetPropulsion()->GetTank(0)->GetContents()*.45359237;
  o.wind=column(exec.GetWinds()->GetWindNED(),s::feet);o.running=exec.GetPropulsion()->GetEngine(0)->GetRunning();
  std::cout<<"{\"event\":\"zero-time-observation\",\"phase\":"<<s::quoted(phase)<<",\"cg_ecef_m\":";s::emit_vec(std::cout,o.cg_ecef);
  std::cout<<",\"cg_geodetic\":";s::emit_vec(std::cout,s::geod_vec(o.cg));std::cout<<",\"body_to_ned\":";s::emit_mat(std::cout,o.matrix);
  std::cout<<",\"uvw_mps\":";s::emit_vec(std::cout,o.uvw);std::cout<<",\"pqr_radps\":";s::emit_vec(std::cout,o.pqr);std::cout<<",\"wind_mps\":";s::emit_vec(std::cout,o.wind);
  std::cout<<",\"time\":"<<o.time<<",\"fuel_kg\":"<<o.fuel<<",\"running\":"<<(o.running?"true":"false")<<"}\n";
  s::require(o.time==0&&s::finite(o.uvw)&&s::finite(o.pqr)&&s::finite(o.wind)&&s::maxabs(o.wind)==0,"time/wind/nonfinite actual state mismatch");
  check_near(o.cg_ecef,s::decode(r::cg_ecef_words),1e-5,"RunIC ECEF differs from frozen author pose");
  check_near(o.cg_eus,s::decode(r::cg_eus_words),1e-5,"RunIC EUS differs from frozen author pose");
  s::require(std::abs(o.cg.ellipsoid_height_m-s::decode(r::cg_geodetic_words)[2])<=1e-5,"RunIC ellipsoid height differs");
  for(std::size_t i=0;i<9;++i)s::require(std::isfinite(o.matrix[i])&&std::abs(o.matrix[i]-std::bit_cast<double>(r::body_to_ned_words[i]))<=1e-9,"RunIC orientation matrix differs");
  s::require(s::maxabs(o.uvw)<=1e-6&&s::maxabs(o.pqr)<=1e-12,"RunIC changed zero kinematics");
  s::require(std::isfinite(o.fuel)&&std::abs(o.fuel-100)<=1e-10,"original fuel changed");return o;
}
void hold_controls(j::FGFDMExec& exec) {
  for(const auto* key:{"fcs/aileron-cmd-norm","fcs/elevator-cmd-norm","fcs/rudder-cmd-norm","fcs/pitch-trim-cmd-norm","fcs/throttle-cmd-norm"})exec.SetPropertyValue(key,0);
  // Original direct-thrust Session uses the property throttle route. Explicit
  // mixture1 is a private held-axis check; it is not piston initialization.
  exec.GetFCS()->SetMixtureCmd(0,1);exec.GetFCS()->SetMixturePos(0,1);
  exec.GetFCS()->SetLBrake(1);exec.GetFCS()->SetRBrake(1);exec.GetFCS()->SetDsCmd(0);
}
void check_controls(j::FGFDMExec& exec) {
  for(const auto* key:{"fcs/aileron-cmd-norm","fcs/elevator-cmd-norm","fcs/rudder-cmd-norm","fcs/pitch-trim-cmd-norm","fcs/throttle-cmd-norm"})s::require(exec.GetPropertyValue(key)==0,"actual held axes changed");
  const auto fcs=exec.GetFCS();s::require(fcs->GetLBrake()==1&&fcs->GetRBrake()==1&&fcs->GetDsCmd()==0&&fcs->GetMixtureCmd(0)==1&&fcs->GetMixturePos(0)==1,"actual held brakes/mixture/steering changed");
}
void final_gear(j::FGFDMExec& exec,const s::Terrain& terrain,const Observation& o) {
  s::g::Boundary boundary(terrain.provider,{{0},"qualification.kawo-start-final-gear"},4);
  const auto cg_floor=terrain.sample(boundary,o.cg);s::require(o.cg.ellipsoid_height_m-cg_floor.surface_height_m>=1,"actual CG clearance below1m");
  const s::Local local(o.cg);const auto reactions=exec.GetGroundReactions();
  for(std::size_t i=0;i<3;++i) {
    const auto gear=reactions->GetGearUnit(static_cast<int>(i));const auto arm=column(gear->GetBodyLocation(),s::feet);
    const auto source_arm=s::model_arms()[i],reference_arm=s::decode(r::nominal_arm_words[i]);
    std::cout<<"{\"event\":\"nominal-arm-correspondence\",\"index\":"<<i<<",\"actual_arm_m\":";s::emit_vec(std::cout,arm);
    std::cout<<",\"source_expected_arm_m\":";s::emit_vec(std::cout,source_arm);
    std::cout<<",\"reference_arm_m\":";s::emit_vec(std::cout,reference_arm);
    std::cout<<",\"source_discrepancy_m\":";s::emit_vec(std::cout,s::minus(arm,source_arm));
    std::cout<<",\"reference_discrepancy_m\":";s::emit_vec(std::cout,s::minus(arm,reference_arm));std::cout<<"}\n";
    check_near(arm,source_arm,1e-12,"actual nominal arm differs from pinned structural-to-body source");
    check_near(arm,s::decode(r::nominal_arm_words[i]),1e-12,"actual nominal arm differs from pre-RunIC reference");
    const auto wheel=s::plus(o.cg_ecef,local.offset(s::rotate(o.matrix,arm)));const auto position=s::inverse(wheel);const auto ground=terrain.sample(boundary,position);
    const double sep=position.ellipsoid_height_m-ground.surface_height_m;const auto point=terrain.frame.project(wheel);
    s::require(sep>=0&&sep<=.25&&s::in_polygon(point[0],point[2])&&ground.material_id==r::wheel_materials[i],"actual gear clearance/material/footprint mismatch");
    // Frozen before output: CG1e-5/component + matrix1e-9 acting on <3.31m
    // L1 source-converted arm, with local-frame/reconstruction rounding margin.
    check_near(wheel,s::decode(r::wheel_ecef_words[i]),2e-5,"actual wheel differs from frozen author geometry");
    std::cout<<"{\"event\":\"actual-gear\",\"index\":"<<i<<",\"body_arm_m\":";s::emit_vec(std::cout,arm);std::cout<<",\"ecef_m\":";s::emit_vec(std::cout,wheel);
    std::cout<<",\"clearance_m\":"<<sep<<",\"surface_height_word\":"<<s::quoted(s::word(ground.surface_height_m))<<",\"material\":"<<s::quoted(ground.material_id)<<",\"wow\":"<<(gear->GetWOW()?"true":"false")<<",\"compression_m\":"<<gear->GetCompLen()*s::feet<<",\"compression_rate_mps\":"<<gear->GetCompVel()*s::feet<<"}\n";
  }
  s::require(boundary.query_count()==4&&!boundary.failed(),"final gear boundary mismatch");
}
}
int main(int argc,char** argv) {
  try {
    s::environment();s::require(argc==4,"usage: runic ABSOLUTE_PAYLOAD ABSOLUTE_RECEIPT ABSOLUTE_ORIGINAL_MODEL_ROOT");s::emit_inputs();s::verify_model(argv[3]);
    s::require(r::payload_sha256==s::m::payload_sha256&&r::receipt_sha256==s::m::receipt_sha256&&s::g::hash(r::author_output_sha256),"frozen reference source/output identity mismatch");
    const s::Terrain terrain(argv[1],argv[2]);const auto requested_geo=s::geod(s::decode(r::cg_geodetic_words));const auto requested_ecef=s::decode(r::cg_ecef_words);const auto rpy=s::decode(r::rpy_words);
    check_near(s::forward(requested_geo),requested_ecef,1e-5,"reference geodetic/ECEF mismatch");
    const auto requested_eus=terrain.frame.project(requested_ecef);check_near(requested_eus,s::decode(r::cg_eus_words),1e-5,"reference EUS mismatch");
    s::require(std::abs(requested_eus[0]-terrain.x)<=1e-5&&std::abs(requested_eus[2]-terrain.z)<=1e-5&&std::abs(rpy[0])<=.2&&std::abs(rpy[1])<=.2&&rpy[2]>=0&&rpy[2]<2*s::c::pi,"reference chainage/orientation domain mismatch");
    // Pure preflight uses frozen source pose and accepted grid before allocation.
    const auto pre=s::evaluate(terrain,{requested_eus[1],rpy[0],rpy[1]});s::clearances(terrain,pre);
    check_near(pre.rpy,rpy,1e-12,"reference true yaw differs from physical centerline");
    loaded_library();Callback* callback=nullptr;
    std::unique_ptr<j::FGFDMExec,Deleter> exec(new j::FGFDMExec(),Deleter{&callback});exec->SetDebugLevel(0);
    const auto root=std::filesystem::path(argv[3]).u8string();exec->SetRootDir(SGPath::fromUtf8(std::string(root.begin(),root.end())));exec->SetAircraftPath(SGPath("aircraft"));exec->SetEnginePath(SGPath("engine"));
    s::require(exec->LoadModel("original-interactive"),"original model failed to load");
    s::require(exec->GetGroundReactions()->GetNumGearUnits()==3&&exec->GetPropulsion()->GetNumEngines()==1&&exec->GetPropulsion()->GetNumTanks()==1,"actual original model topology mismatch");
    callback=new Callback(terrain);exec->GetInertial()->SetGroundCallback(callback);exec->Setdt(1./120);exec->SetPropertyValue("simulation/randomseed",42);exec->GetWinds()->SetTurbType(j::FGWinds::ttNone);
    const auto ic=exec->GetIC();
    // Source-reviewed existing setter: forces ASL mode without ground queries,
    // so staged latitude/longitude never take their partial-pose AGL branches.
    ic->SetAltitudeASLFtIC(requested_geo.ellipsoid_height_m/s::feet);
    ic->SetLatitudeRadIC(std::atan2(requested_ecef[2],std::hypot(requested_ecef[0],requested_ecef[1])));ic->SetLongitudeRadIC(requested_geo.longitude_rad);
    ic->SetPhiRadIC(rpy[0]);ic->SetThetaRadIC(rpy[1]);ic->SetPsiRadIC(rpy[2]);ic->SetPRadpsIC(0);ic->SetQRadpsIC(0);ic->SetRRadpsIC(0);
    ic->SetUBodyFpsIC(0);ic->SetVBodyFpsIC(0);ic->SetWBodyFpsIC(0);ic->SetWindNEDFpsIC(0,0,0);
    double radial=requested_geo.ellipsoid_height_m/s::feet;bool solved=false;
    for(unsigned iteration=0;iteration<12;++iteration){ic->SetAltitudeASLFtIC(radial);const double error=requested_geo.ellipsoid_height_m-geodetic(ic->GetPosition()).ellipsoid_height_m;
      std::cout<<"{\"event\":\"pre-RunIC-radius\",\"iteration\":"<<iteration<<",\"error_m\":"<<error<<",\"radial_asl_ft\":"<<radial<<"}\n";
      if(std::isfinite(error)&&std::abs(error)<1e-8){solved=true;break;}s::require(std::isfinite(error),"nonfinite radial IC solve");radial=s::sum(radial,s::div(error,s::feet));}
    s::require(solved,"bounded pre-RunIC radial solve failed");exec->GetPropulsion()->SetFuelFreeze(true);callback->phase="RunIC";
    s::require(exec->RunIC()&&!callback->boundary.failed(),"actual RunIC failed");const auto after_ic=observe(*exec,terrain,"RunIC");(void)after_ic;
    callback->phase="InitRunning";exec->GetPropulsion()->InitRunning(-1);const auto after_running=observe(*exec,terrain,"InitRunning");s::require(after_running.running,"direct thrust not prestarted");
    callback->phase="held-controls";hold_controls(*exec);check_controls(*exec);observe(*exec,terrain,"held-controls");
    callback->phase="InitializeDerivatives";exec->GetPropagate()->InitializeDerivatives();exec->GetPropulsion()->SetFuelFreeze(false);const auto final=observe(*exec,terrain,"InitializeDerivatives/fuel-unfreeze");check_controls(*exec);s::require(final.running,"direct thrust running state lost");
    final_gear(*exec,terrain,final);s::require(!callback->boundary.failed()&&callback->boundary.query_count()>0,"callback was not actually exercised");
    const auto queries=callback->boundary.query_count();exec.reset();s::require(callback==nullptr,"actual executive destruction incomplete");
    // Vendor RunIC invokes suspended-integration Run internally. This count is
    // only the probe's external advancing Run calls, never a vendor-call claim.
    s::verify_model(argv[3]);std::cout<<"{\"event\":\"runic-qualified\",\"passed\":true,\"sim_time\":0,\"external_advancing_run_calls\":0,\"runic_calls\":1,\"callback_queries\":"<<queries<<",\"author_output_sha256\":"<<s::quoted(r::author_output_sha256)<<",\"runtime_admitted\":false,\"dynamic_ground_contact_qualified\":false}\n";
    s::require(std::cout.good(),"qualifier output failed");return 0;
  } catch(const std::exception& error) {
    std::cout<<"{\"event\":\"runic-refused\",\"passed\":false,\"reason\":"<<s::quoted(error.what())<<"}\n";std::cerr<<"runic refused: "<<error.what()<<'\n';return 1;
  } catch(...) {
    std::cout<<"{\"event\":\"runic-refused\",\"passed\":false,\"reason\":\"nonstandard bounded-arithmetic failure\"}\n";return 1;
  }
}
