#include "interactive_worker.hpp"
#ifndef KAWO_START_REFERENCE_HEADER
#error The independently frozen 1bdfe61c start reference is required
#endif
#include KAWO_START_REFERENCE_HEADER
#include <bit>
#include <charconv>
#include <iostream>

namespace i=flight::interactive;
namespace b=flight::bridge;
namespace c=flight::contracts::v1;
namespace r=kawo_start_reference;
namespace {
int checks=0;
void check(bool condition,const char* why){++checks;if(!condition)throw std::runtime_error(why);}
double scalar(std::uint64_t bits){return std::bit_cast<double>(bits);}
i::Vec decode(const std::array<std::uint64_t,3>& words){return {scalar(words[0]),scalar(words[1]),scalar(words[2])};}
void near_vector(i::Vec actual,i::Vec expected,double budget,const char* why){for(std::size_t j=0;j<3;++j)check(std::isfinite(actual[j])&&std::abs(actual[j]-expected[j])<=budget,why);}
i::Config geographic(const std::filesystem::path& root,const std::shared_ptr<const i::PreparedWorld>& world){i::Config config;config.model_root=root;config.geographic_world=world;config.world_choice=i::WorldChoice::kawo_prototype_v1;config.session_id="test.kawo-actual";return config;}
template<class F> bool refused(F&& operation){try{operation();return false;}catch(...){return true;}}
void actual(const std::filesystem::path& root,unsigned ticks){
  const auto world=i::load_kawo_world(root);check(world&&world->bound_to(root),"actual immutable world bound");
  const auto recipe=world->start_position();check(std::bit_cast<std::uint64_t>(recipe.latitude_rad)==r::cg_geodetic_words[0]&&std::bit_cast<std::uint64_t>(recipe.longitude_rad)==r::cg_geodetic_words[1]&&std::bit_cast<std::uint64_t>(recipe.ellipsoid_height_m)==r::cg_geodetic_words[2],"independent exact recipe words");
  check(world->identity().prepared_surface_sha256==r::payload_sha256&&r::receipt_sha256=="cb1e0b28384aeb1c11173d991b5790a8a16e64953c2c479be6b07136c5f489f0"&&r::author_output_sha256=="1f6a464c85a9a01e5314d4eb71ba652ba00931006d89f16412ccdf5c0453b4f2","independent start source identity");
  auto crossed=geographic(root,world);crossed.start=i::Start::airborne;
  check(refused([&]{i::Session session(crossed);}),"crossed geographic named start refused");
  crossed=geographic(root,world);crossed.wind_profile=i::SteadyWindProfile::from_north;
  check(refused([&]{i::Session session(crossed);}),"crossed geographic wind refused");
  crossed=geographic(root,world);crossed.angular_method=i::AngularMethod::legacy_euler;
  check(refused([&]{i::Session session(crossed);}),"explicit geographic angular override refused");
  crossed=geographic(root,world);crossed.surface=std::make_shared<const i::AnalyticSurface>(i::SurfaceConfig{},i::prepared_identity(i::SurfaceConfig{}));
  check(refused([&]{i::Session session(crossed);}),"analytic/geographic dual binding refused");
  crossed=geographic(root,world);crossed.geographic_world.reset();
  check(refused([&]{i::Session session(crossed);}),"null geographic binding refused");
  crossed=geographic(root,world);crossed.world_choice=i::WorldChoice::original_synthetic;
  check(refused([&]{i::Session session(crossed);}),"synthetic with geographic binding refused");
  b::InteractiveWorker worker(geographic(root,world));
  const auto initial=worker.call([world](i::Session& session){
    const auto state=session.latest();const auto position=decode(r::cg_geodetic_words);const auto held=session.held();
    check(session.live()&&state.header.tick.value==0&&state.elapsed_s==0&&state.clock.tick_rate_hz==120&&state.clock.purpose==c::ClockPurpose::runtime,"actual tick0 clock/live");
    check(!session.angular_integration_method()&&session.profile()==i::Profile::legacy,"actual original model method");
    check(c::valid(state.position)&&std::abs(state.position.ellipsoid_height_m-position[2])<=1e-5,"actual requested canonical ellipsoid height");
    near_vector({state.ecef_position_m.x,state.ecef_position_m.y,state.ecef_position_m.z},decode(r::cg_ecef_words),1e-5,"independent tick0 canonical ECEF");near_vector(world->project(state.ecef_position_m),decode(r::cg_eus_words),1e-5,"independent tick0 anchor EUS");
    const auto orientation=state.orientation_body_to_ned;
    for(unsigned column=0;column<3;++column){c::BodyPosition arm{};if(column==0)arm.x=1;else if(column==1)arm.y=1;else arm.z=1;const auto ned=c::rotate_body_to_ned(orientation,arm);near_vector({ned.x,ned.y,ned.z},{scalar(r::body_to_ned_words[column]),scalar(r::body_to_ned_words[3+column]),scalar(r::body_to_ned_words[6+column])},1e-9,"independent tick0 full rotation matrix");}
    near_vector({state.velocity_body_mps.x,state.velocity_body_mps.y,state.velocity_body_mps.z},{0,0,0},1e-6,"actual zero startup velocity");near_vector({state.angular_rate_body_radps.x,state.angular_rate_body_radps.y,state.angular_rate_body_radps.z},{0,0,0},1e-12,"actual zero startup rates");
    check(held.roll==0&&held.pitch==0&&held.yaw==0&&held.throttle==0&&held.mixture==1&&held.left_brake==1&&held.right_brake==1&&held.trim==0,"actual held recipe axes");
    check(state.contacts.size()==3,"actual three gear contacts");
    for(std::size_t j=0;j<3;++j){const auto arm=state.contacts[j].point_body_m;check(std::bit_cast<std::uint64_t>(arm.x)==r::nominal_arm_words[j][0]&&std::bit_cast<std::uint64_t>(arm.y)==r::nominal_arm_words[j][1]&&std::bit_cast<std::uint64_t>(arm.z)==r::nominal_arm_words[j][2],"independent actual arm words");}
    const auto observations=i::SessionTestAccess::initialization(session);for(const auto& observation:observations){near_vector({observation.ground_body_mps.x,observation.ground_body_mps.y,observation.ground_body_mps.z},{0,0,0},1e-6,"actual startup stages zero velocity");near_vector({observation.total_wind_mps.x,observation.total_wind_mps.y,observation.total_wind_mps.z},{0,0,0},0,"actual startup stages calm");}
    const auto count=i::SessionTestAccess::geographic_queries(session);check(count>0,"installed runtime geographic callbacks exercised");const auto reply=b::interactive_sample(session,*world->provider());check(reply.live&&reply.ground_valid&&reply.clearance_m>=1,"actual source-bound ground readback");
    std::cout<<"{\"event\":\"kawo-tick0\",\"callback_queries\":"<<count<<",\"prepared_world_sha256\":\""<<world->identity().prepared_surface_sha256<<"\",\"world_manifest_sha256\":\""<<world->identity().world.sha256<<"\",\"aircraft\":"<<reply.aircraft<<"}\n";return reply;
  });
  check(initial.live&&initial.ground_valid,"actual worker copied initial reply");
  const auto completed=worker.call([world,ticks](i::Session& session){for(unsigned n=0;n<ticks;++n){const auto step=session.step_fixed();check(step.status==i::Status::completed,"actual fixed tick unexpectedly blocked/discarded");}auto result=b::interactive_sample(session,*world->provider());check(session.latest().header.tick.value==ticks,"no hidden/excess native ticks");
    if(ticks==240){
      check(result.live&&result.ground_valid,"actual contact completion retains live ground authority");
      const auto& final_state=session.latest();
      check(final_state.validity==c::Validity::valid&&c::valid(final_state.orientation_body_to_ned),"actual contact completion has valid orientation/state");
      check(final_state.contacts.size()==3,"actual contact completion retains three gear contacts");
      for(const auto& contact:final_state.contacts){
        check(contact.on_ground&&c::finite(contact.force_body_n),"actual final gear is on ground with finite force");
        const auto force_ned=c::rotate_body_to_ned(final_state.orientation_body_to_ned,contact.force_body_n);
        check(c::finite(force_ned)&&force_ned.z<0,"actual final gear supplies upward support");
      }
    }
    std::cout<<"{\"event\":\"kawo-completed\",\"requested_ticks\":"<<ticks<<",\"callback_queries\":"<<i::SessionTestAccess::geographic_queries(session)<<",\"aircraft\":"<<result.aircraft<<"}\n";session.close();const auto historical=b::interactive_sample(session,*world->provider());check(!historical.live&&!historical.ground_valid,"closed publication cannot revive provider authority");return historical;});
  check(!completed.live&&!completed.ground_valid,"historical copied close reply");worker.close();
  check(refused([&]{(void)worker.call([](i::Session& session){(void)session;return b::InteractiveReply{};});}),"actual joined mailbox refuses calls");
}
}
int main(int argc,char** argv){try{
  check(argc==3||argc==4,"usage: kawo_journey actual|refuse ABSOLUTE_MODEL_ROOT [ticks0..240]");const std::filesystem::path root=argv[2];check(root.is_absolute(),"absolute actual model root required");
  const std::string_view mode=argv[1];if(mode=="refuse"){check(argc==3,"refusal mode has no tick parameter");check(refused([&]{(void)i::load_kawo_world(root);}),"malformed/missing/crossed installed pack must refuse");}
  else {check(mode=="actual","unknown proof mode");unsigned ticks=1;if(argc==4){const std::string_view value=argv[3];const auto parsed=std::from_chars(value.data(),value.data()+value.size(),ticks);check(parsed.ec==std::errc{}&&parsed.ptr==value.data()+value.size()&&ticks<=240,"bounded native tick argument");}actual(root,ticks);}
  std::cout<<"{\"event\":\"kawo-native-checks\",\"checks\":"<<checks<<",\"passed\":true,\"pilot_or_phase_acceptance\":false}\n";return 0;
}catch(const std::exception& e){std::cerr<<"KAWO actual proof refused after "<<checks<<" checks: "<<e.what()<<'\n';return 1;}}
