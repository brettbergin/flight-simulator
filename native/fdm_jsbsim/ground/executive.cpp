#include "executive.hpp"
#include <flight/fdm/protocol.hpp>
#include <flight/fdm/model.hpp>
#include <FGFDMExec.h>
#include <initialization/FGInitialCondition.h>
#include <input_output/FGGroundCallback.h>
#include <models/FGAccelerations.h>
#include <models/FGFCS.h>
#include <models/FGGroundReactions.h>
#include <models/FGInertial.h>
#include <models/FGMassBalance.h>
#include <models/FGPropagate.h>
#include <iomanip>
#include <fstream>
#include <sstream>

namespace flight::ground::proof {
namespace j=JSBSim;namespace f=flight::fdm;
namespace {
constexpr double slug_to_kg=14.5939029372064;
void verify_fixture(const std::filesystem::path& root) {
  const auto base=std::filesystem::canonical(root);
  const auto path=std::filesystem::canonical(base/"aircraft/ground-cart/ground-cart.xml");
  const auto relative=path.lexically_relative(base);
  if(relative.empty()||*relative.begin()==".."||!std::filesystem::is_regular_file(path)||std::filesystem::file_size(path)!=fixture_bytes)
    throw std::invalid_argument("Ground fixture path/size mismatch");
  std::ifstream input(path,std::ios::binary);std::vector<std::uint8_t> bytes(fixture_bytes);
  input.read(reinterpret_cast<char*>(bytes.data()),static_cast<std::streamsize>(bytes.size()));
  if(!input||f::sha256(bytes)!=fixture_sha256)throw std::invalid_argument("Ground fixture hash mismatch");
}
c::GeodeticPosition geodetic(const j::FGLocation& input) {
  auto location=input;location.SetEllipse(c::geodesy::semi_major_m/.3048,c::geodesy::semi_minor_m/.3048);
  return {location.GetGeodLatitudeRad(),location.GetLongitude(),location.GetGeodAltitude()*.3048};
}
c::EcefPosition ecef(const j::FGLocation& location) { return {location(1)*.3048,location(2)*.3048,location(3)*.3048}; }
}
class GroundExecutive::Impl {
 public:
  class Callback final:public j::FGGroundCallback {
   public:
    explicit Callback(Impl& owner):owner_(owner){}
    double GetAGLevel(double,const j::FGLocation& query,j::FGLocation& contact,j::FGColumnVector3& normal,j::FGColumnVector3& velocity,j::FGColumnVector3& angular) const override {
      // JSBSim Unbind copies property getters, including AGL, during teardown.
      // An exception there would terminate from its noexcept destructor. The
      // deleter marks terminal disposal before deletion: no provider, Run,
      // force computation or publication can consume these detached getter values.
      if(owner_.disposing){contact=query;normal={0,0,0};velocity={0,0,0};angular={0,0,0};return 0;}
      if(!owner_.boundary)throw std::runtime_error("No prepared ground boundary");
      const auto position=geodetic(query);const auto result=owner_.boundary->sample(position);
      const auto* valid_sample=std::get_if<c::ValidGround>(&result.sample);
      if(!valid_sample)throw std::runtime_error("Unexpected ground miss during executive mutation");
      contact=query;contact.SetEllipse(c::geodesy::semi_major_m/.3048,c::geodesy::semi_minor_m/.3048);
      contact.SetPositionGeodetic(position.longitude_rad,position.latitude_rad,valid_sample->surface_height_m/.3048);
      const auto n=Basis(position).ned_to_ecef(valid_sample->normal_ned);normal={n[0],n[1],n[2]};velocity={0,0,0};angular={0,0,0};
      return (position.ellipsoid_height_m-valid_sample->surface_height_m)/.3048;
    }
   private:Impl& owner_;
  };
  bool disposing{};
  struct Deleter {bool* disposing;void operator()(j::FGFDMExec* value)const noexcept {if(value){*disposing=true;delete value;}}};
  std::shared_ptr<const AnalyticSurface> surface;std::unique_ptr<v1::Boundary> boundary;
  std::unique_ptr<j::FGFDMExec,Deleter> executive{nullptr,Deleter{&disposing}};c::FixedClock clock;c::ClockConfig config;
  c::AircraftSnapshot publication;ContactDiagnostics diagnostic;GroundControls held_controls;
  explicit Impl(std::filesystem::path root,std::shared_ptr<const AnalyticSurface> provider,std::uint32_t hz,GroundInitial initial)
   :surface(std::move(provider)),clock({hz,c::ClockPurpose::convergence}),config{hz,c::ClockPurpose::convergence} {
    if(!surface||!std::isfinite(initial.clearance_m)||initial.clearance_m<1||initial.clearance_m>3||
       !std::isfinite(initial.forward_mps)||std::abs(initial.forward_mps)>10||!std::isfinite(initial.down_mps)||std::abs(initial.down_mps)>3)
      throw std::invalid_argument("Unsupported ground proof initial conditions");
    verify_fixture(root);
    boundary=std::make_unique<v1::Boundary>(surface,c::SampleHeader{{0},"ground-proof"},4096);
    executive.reset(new j::FGFDMExec());executive->SetDebugLevel(0);
    const auto utf8=root.u8string();executive->SetRootDir(SGPath::fromUtf8(std::string(utf8.begin(),utf8.end())));executive->SetAircraftPath(SGPath("aircraft"));
    if(!executive->LoadModel("ground-cart"))throw std::runtime_error("Original ground fixture load failed");
    executive->Setdt(clock.integration_step_s());executive->GetInertial()->SetGroundCallback(new Callback(*this));
    const auto ic=executive->GetIC();const auto origin=surface->config().anchor;
    ic->SetGeodLatitudeRadIC(origin.latitude_rad);ic->SetLongitudeRadIC(origin.longitude_rad);
    if(initial.align_to_slope) {
      ic->SetThetaRadIC(std::atan(surface->config().slope_north));
      ic->SetPhiRadIC(-std::atan(surface->config().slope_east/std::sqrt(1+std::pow(surface->config().slope_north,2))));
    }
    // Callback consumes ellipsoid heights; this setter solves its requested AGL.
    ic->SetAltitudeAGLFtIC(initial.clearance_m/.3048);ic->SetUBodyFpsIC(initial.forward_mps/.3048);ic->SetWBodyFpsIC(initial.down_mps/.3048);
    if(!executive->RunIC()||boundary->failed())throw std::runtime_error("Ground fixture initialization failed");
    publication=snapshot({0});diagnostic=contact_diagnostics();
  }
  c::AircraftSnapshot snapshot(c::Tick tick) const {
    const auto p=executive->GetPropagate();const auto m=executive->GetMassBalance();const auto& location=p->GetLocation();
    const auto& uvw=p->GetUVW();const auto& rate=p->GetPQR();const auto& derivative=executive->GetAccelerations()->GetUVWdot();
    const auto& cg=m->GetXYZcg();std::array<double,9> matrix{};const auto& transform=p->GetTb2l();
    for(unsigned i=0;i<3;++i)for(unsigned k=0;k<3;++k)matrix[3*i+k]=transform(i+1,k+1);
    c::AircraftSnapshot s;s.header={tick,"ground-proof"};s.clock=config;s.elapsed_s=static_cast<double>(tick.value)/config.tick_rate_hz;
    s.position=geodetic(location);s.ecef_position_m=ecef(location);s.orientation_body_to_ned=f::body_to_ned_from_matrix(matrix);
    s.velocity_body_mps={uvw(1)*.3048,uvw(2)*.3048,uvw(3)*.3048};s.angular_rate_body_radps={rate(1),rate(2),rate(3)};
    s.acceleration_body_mps2=f::earth_acceleration_body_mps2({derivative(1)*.3048,derivative(2)*.3048,derivative(3)*.3048},s.angular_rate_body_radps,s.velocity_body_mps);
    s.mass_kg=m->GetMass()*slug_to_kg;s.center_of_gravity_body_m=f::structural_cg_inches_to_body_datum_m(cg(1),cg(2),cg(3));s.validity=c::Validity::valid;
    const auto gears=executive->GetGroundReactions();
    for(int i=0;i<3;++i) {
      const auto gear=gears->GetGearUnit(i);const bool wow=gear->GetWOW();
      const auto arm=wow?m->StructuralToBody(gear->GetActingLocation()):gear->GetBodyLocation();
      // These getters assemble the already solved Lagrange multipliers; they do
      // not call FGLGear::GetBodyForces, query terrain, or rerun contact geometry.
      const c::BodyForce force{c::units::pounds_force_to_newtons(gear->GetBodyXForce()),c::units::pounds_force_to_newtons(gear->GetBodyYForce()),c::units::pounds_force_to_newtons(gear->GetBodyZForce())};
      s.contacts.push_back({i==0?"gear.nose":i==1?"gear.left":"gear.right",{arm(1)*.3048,arm(2)*.3048,arm(3)*.3048},force,wow});
    }
    if(!c::valid(s)||c::magnitude(s.velocity_body_mps)>20||c::magnitude(s.angular_rate_body_radps)>2||c::magnitude(s.acceleration_body_mps2)>400)
      throw std::runtime_error("Ground result outside finite proof domain");
    return s;
  }
  ContactDiagnostics contact_diagnostics() const {
    ContactDiagnostics out;for(int i=0;i<3;++i){const auto gear=executive->GetGroundReactions()->GetGearUnit(i);out.compression_m[i]=gear->GetCompLen()*.3048;out.compression_rate_mps[i]=gear->GetCompVel()*.3048;
      const auto prefix="gear/unit["+std::to_string(i)+"]/";
      out.static_friction[i]=executive->GetPropertyValue(prefix+"static_friction_coeff");out.dynamic_friction[i]=executive->GetPropertyValue(prefix+"dynamic_friction_coeff");}
    out.queries=boundary->query_count();return out;
  }
  StepStatus step(GroundControls controls) {
    if(!executive)return StepStatus::discarded;
    if(!std::isfinite(controls.steering)||std::abs(controls.steering)>1||!std::isfinite(controls.left_brake)||controls.left_brake<0||controls.left_brake>1||
       !std::isfinite(controls.right_brake)||controls.right_brake<0||controls.right_brake>1)throw std::invalid_argument("Invalid proof ground controls");
    const auto next=*c::next_tick(clock.completed_tick());const double dt=clock.integration_step_s();
    // Gear radius <2.5m. Domain max20m/s, max2rad/s, max400m/s²,
    // plus 2cm numerical allowance: certify entire horizontal swept footprint.
    const double guard=2.5+(20+2*2.5)*dt+.5*400*dt*dt+.02;
    if(!surface->covers(publication.ecef_position_m,guard))return StepStatus::coverage_blocked;
    boundary=std::make_unique<v1::Boundary>(surface,c::SampleHeader{next,"ground-proof"},256);
    try {
      const auto p=executive->GetPropagate();const auto location=p->GetLocation();
      const auto cg_sample=boundary->sample(publication.position);
      if(!std::holds_alternative<c::ValidGround>(cg_sample.sample))return StepStatus::coverage_blocked;
      std::array<c::ValidGround,3> materials;
      for(int i=0;i<3;++i){const auto gear=executive->GetGroundReactions()->GetGearUnit(i);const auto wheel=location.LocalToLocation(p->GetTb2l()*gear->GetBodyLocation());
        const auto sample=boundary->sample(geodetic(wheel));if(!std::holds_alternative<c::ValidGround>(sample.sample))return StepStatus::coverage_blocked;materials[i]=std::get<c::ValidGround>(sample.sample);}
      // No mutation occurred before all preflight/certificate/material checks.
      for(int i=0;i<3;++i){const auto prefix="gear/unit["+std::to_string(i)+"]/";
        executive->SetPropertyValue(prefix+"static_friction_coeff",materials[i].static_friction);
        executive->SetPropertyValue(prefix+"dynamic_friction_coeff",materials[i].dynamic_friction);}
      executive->GetFCS()->SetLBrake(controls.left_brake);executive->GetFCS()->SetRBrake(controls.right_brake);executive->GetFCS()->SetDsCmd(controls.steering);
      if(!executive->Run()||boundary->failed())throw std::runtime_error("Ground executive mutation failed");
      auto result=snapshot(next);auto next_diagnostics=contact_diagnostics();
      const auto a=surface->coordinates(publication.ecef_position_m),b=surface->coordinates(result.ecef_position_m);
      if(std::hypot(b.x-a.x,b.y-a.y)>guard-2.5||!surface->covers(result.ecef_position_m,2.5))throw std::runtime_error("Ground movement exceeded certified sweep");
      if(!clock.advance())throw std::runtime_error("Ground clock failed");
      publication=std::move(result);diagnostic=next_diagnostics;held_controls=controls;return StepStatus::completed;
    } catch(const std::exception& error) {
      std::fprintf(stderr,"Ground terminal: %s\n",error.what());
      // Preflight malformed/throwing providers and any partial Run are terminal.
      // No checkpoint rollback is claimed: destroy the solver, retain last owned publication.
      executive.reset();return StepStatus::discarded;
    }
  }
};
GroundExecutive::GroundExecutive(std::filesystem::path root,std::shared_ptr<const AnalyticSurface> surface,std::uint32_t hz,GroundInitial initial):impl_(std::make_unique<Impl>(std::move(root),std::move(surface),hz,initial)){}
GroundExecutive::~GroundExecutive()=default;
StepStatus GroundExecutive::step(GroundControls controls){return impl_->step(controls);}
const c::AircraftSnapshot& GroundExecutive::latest()const{return impl_->publication;}
const ContactDiagnostics& GroundExecutive::diagnostics()const{return impl_->diagnostic;}
GroundControls GroundExecutive::held()const{return impl_->held_controls;}
bool GroundExecutive::live()const{return bool(impl_->executive);}
std::string snapshot_json(const c::AircraftSnapshot& snapshot) {
  if(!c::valid(snapshot)||snapshot.validity!=c::Validity::valid)throw std::invalid_argument("Invalid ground publication");
  auto base=snapshot;base.contacts.clear();auto text=f::transport::json(base);std::ostringstream contacts;contacts<<std::setprecision(17)<<"\"contacts\":[";
  for(std::size_t i=0;i<snapshot.contacts.size();++i){const auto& item=snapshot.contacts[i];if(i)contacts<<',';
    contacts<<"{\"id\":\""<<item.id<<"\",\"point_body_m\":{\"x\":"<<item.point_body_m.x<<",\"y\":"<<item.point_body_m.y<<",\"z\":"<<item.point_body_m.z<<"},\"force_body_n\":{\"x\":"<<item.force_body_n.x<<",\"y\":"<<item.force_body_n.y<<",\"z\":"<<item.force_body_n.z<<"},\"on_ground\":"<<(item.on_ground?"true":"false")<<'}';}
  contacts<<']';const auto offset=text.find("\"contacts\":[]");if(offset==std::string::npos)throw std::runtime_error("Ground snapshot serializer layout drift");text.replace(offset,13,contacts.str());return text;
}
} // namespace flight::ground::proof
