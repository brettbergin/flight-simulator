#include <flight/reconstruction/recipe.hpp>
#include <flight/fdm/model.hpp>
#include <chrono>
#include <fstream>
#include <iostream>
#include <stdexcept>

namespace p=flight::reconstruction::proof;namespace f=flight::fdm;namespace c=flight::contracts::v1;
namespace {
void text_file(const std::filesystem::path& path,const std::string& text) {
  p::write_checked(path,std::span(reinterpret_cast<const std::uint8_t*>(text.data()),text.size()));
}
std::string chain(const std::string& previous,const f::Session& session) {
  const auto value=previous+f::transport::json(session.latest_snapshot())+'\n'+f::transport::json(session.latest_atmosphere())+'\n'+f::transport::json(session.diagnostics());
  return f::sha256(std::span(reinterpret_cast<const std::uint8_t*>(value.data()),value.size()));
}
void logs(const p::Recipe& recipe,const f::Session& session,const std::filesystem::path& out) {
  std::string admitted;
  for(const auto& record:recipe.admissions) {
    admitted+="{\"received_after_tick\":\""+std::to_string(record.received_after_tick.value)+"\",\"input\":";
    if(const auto* registration=std::get_if<p::Registration>(&record.input))admitted+="{\"kind\":\"register-host-source\",\"source_id\":\""+registration->source_id+"\",\"authority\":"+std::to_string(static_cast<unsigned>(registration->authority))+"}";
    else if(const auto* packet=std::get_if<c::ControlCommand>(&record.input))admitted+=f::transport::json(*packet);
    else {
      const auto& control=std::get<c::SessionControl>(record.input);admitted+="{\"type\":\"SessionControl\",\"schema_version\":1,\"tick\":\""+std::to_string(control.header.tick.value)+"\",\"session_id\":\""+control.header.session_id+"\",\"sequence\":\""+std::to_string(control.sequence.value)+"\",\"source_id\":\""+control.source_id+"\",\"payload\":";
      if(const auto* pause=std::get_if<c::PauseControl>(&control.payload))admitted+=std::string("{\"kind\":\"pause\",\"paused\":")+(pause->paused?"true}":"false}");
      else admitted+="{\"kind\":\"time_scale\",\"scale\":"+std::to_string(std::get<c::TimeScaleControl>(control.payload).scale)+"}";
      admitted+="}";
    }
    admitted+="}\n";
  }
  text_file(out/"admissions.ndjson",admitted);std::string events;for(const auto& event:session.event_log())events+=f::transport::json(event)+'\n';text_file(out/"events.ndjson",events);
}
void identity_check(const f::Session& session,const p::Identity& id) {
  const auto& init=session.initialization();if(init.source_fingerprint!=id[3]||init.compiler!=id[5]||init.library_version!=id[6])throw std::invalid_argument("Actual adapter identity mismatch");
}
struct Recording {
  f::Session session;p::Recipe recipe;
  Recording(f::SessionConfig cfg,p::Recipe initial):session(std::move(cfg)),recipe(std::move(initial)){}
  void input(p::Input value) {
    p::Admission admission{session.latest_snapshot().header.tick,std::move(value)};p::admit(session,admission);recipe.admissions.push_back(std::move(admission));
  }
};
c::ControlCommand command(const f::SessionConfig& cfg,c::PilotAxes a,std::uint64_t tick,std::uint64_t seq,std::string source="pilot.controls") {
  return {{{tick},cfg.session_id},{seq},std::move(source),c::Authority::pilot,{"unassisted",{}},a};
}
c::SessionControl lifecycle(const f::SessionConfig& cfg,std::uint64_t tick,std::uint64_t seq,std::variant<c::PauseControl,c::TimeScaleControl> value) {
  return {{{tick},cfg.session_id},{seq},cfg.lifecycle_source,std::move(value)};
}
std::string reconstruct_to_cut(f::Session& session,const p::Recipe& recipe,std::int64_t& step_ns) {
  std::size_t next=0;std::string digest(64,'0');
  for(std::uint64_t boundary=0;boundary<=recipe.checkpoint_tick.value;++boundary) {
    while(next<recipe.admissions.size()&&recipe.admissions[next].received_after_tick.value==boundary)p::admit(session,recipe.admissions[next++]);
    if(boundary==recipe.checkpoint_tick.value)break;
    const auto started=std::chrono::steady_clock::now();const auto step=session.step_fixed();step_ns+=std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now()-started).count();
    if(!step.stepped) {
      throw std::invalid_argument("Replay history pauses before next required physics step");
    }
    digest=chain(digest,session);
  }
  if(next!=recipe.admissions.size()||session.step_fixed().stepped) {
    throw std::invalid_argument("Replay did not reach canonical paused boundary");
  }
  return digest;
}
int rejects=0;
template<class Fn>void reject(Fn fn) {bool caught=false;try{fn();}catch(const std::exception&){caught=true;}if(!caught)throw std::runtime_error("Negative case unexpectedly accepted");++rejects;}
void negative_tests(const p::Recipe& recipe,const p::Bytes& bytes,const std::filesystem::path& root) {
  for(std::size_t size=0;size<bytes.size();++size)reject([&]{(void)p::decode(std::span(bytes).first(size),recipe.identity);});
  auto corrupt=bytes;corrupt[corrupt.size()/2]^=1;reject([&]{(void)p::decode(corrupt,recipe.identity);});
  auto trailing=bytes;trailing.push_back(0);reject([&]{(void)p::decode(trailing,recipe.identity);});
  for(std::size_t i=0;i<recipe.identity.size();++i) {auto wrong=recipe.identity;wrong[i][0]=wrong[i][0]=='a'?'b':'a';reject([&]{(void)p::decode(bytes,wrong);});}
  auto newer=bytes;newer[8]=2;const auto checksum=f::sha256(std::span(newer).first(newer.size()-64));std::copy(checksum.begin(),checksum.end(),newer.end()-64);reject([&]{(void)p::decode(newer,recipe.identity);});
  auto invalid=recipe;invalid.admissions.back().received_after_tick={0};reject([&]{(void)p::encode(invalid);});
  invalid=recipe;invalid.admissions.pop_back();reject([&]{(void)p::encode(invalid);});
  invalid=recipe;invalid.checkpoint_tick={72001};reject([&]{(void)p::encode(invalid);});
  invalid=recipe;invalid.admissions.insert(invalid.admissions.begin()+1,invalid.admissions.front());
  reject([&]{auto decoded=p::decode(p::encode(invalid),recipe.identity);f::Session session(p::configuration(decoded,root));std::int64_t ns=0;(void)reconstruct_to_cut(session,decoded,ns);});
  invalid=recipe;auto& first=std::get<c::ControlCommand>(invalid.admissions[1].input);first.assistance.active={"auto-rudder"};reject([&]{(void)p::encode(invalid);});
  invalid=recipe;std::get<c::ControlCommand>(invalid.admissions[2].input).sequence={1};
  reject([&]{f::Session session(p::configuration(invalid,root));std::int64_t ns=0;(void)reconstruct_to_cut(session,invalid,ns);});
}
void continuation(f::Session& session,const f::SessionConfig& cfg,const std::filesystem::path& out) {
  const auto axes=session.initialization().solved_controls;
  if(session.submit(command(cfg,axes,72030,5)).rejection!=c::CommandRejection::duplicate)throw std::runtime_error("Restored command sequence gate lost");
  if(!session.submit(command(cfg,axes,72030,6)).queued)throw std::runtime_error("Restored command sequence gate cannot continue");
  if(session.apply(lifecycle(cfg,72000,80,c::PauseControl{false}))!=c::SessionControlRejection::duplicate)throw std::runtime_error("Restored lifecycle sequence gate lost");
  if(session.apply(lifecycle(cfg,72000,82,c::PauseControl{false}))!=c::SessionControlRejection::none)throw std::runtime_error("Restored pause cannot resume");
  std::string digest(64,'0');std::ofstream trace(out/"continuation.ndjson",std::ios::binary|std::ios::trunc);std::uint64_t applied=0;
  for(int i=1;i<=7200;++i) {
    const auto result=session.step_fixed();if(!result.stepped)throw std::runtime_error("Continuation unexpectedly paused");digest=chain(digest,session);
    for(const auto& packet:result.applied_commands){trace<<f::transport::json(packet)<<'\n';++applied;}
    if(i%120==0)trace<<f::transport::json(result.aircraft)<<'\n'<<f::transport::json(result.atmosphere)<<'\n'<<f::transport::json(session.diagnostics())<<'\n';
  }
  trace.close();if(!trace||applied!=3)throw std::runtime_error("Continuation write/pending command count");text_file(out/"continuation.sha256",digest+'\n');
  text_file(out/"final.ndjson",f::transport::json(session.latest_snapshot())+'\n'+f::transport::json(session.latest_atmosphere())+'\n'+f::transport::json(session.diagnostics())+'\n');
}
}
int main(int argc,char** argv) {
  try {
    if(argc==5&&std::string(argv[1])=="identify") {
      auto request=f::transport::decode(p::read_bounded(argv[3]),argv[2]);request.config.future_horizon_ticks=144000;f::Session session(std::move(request.config));text_file(argv[4],f::transport::json(session.initialization())+'\n');return 0;
    }
    if(argc!=6)throw std::invalid_argument("Usage: reconstruction_proof baseline|reconstruct <model> <request|recipe> <identity> <output-dir>");
    const std::string mode=argv[1];const std::filesystem::path root=argv[2],out=argv[5];const auto id=p::read_identity(p::read_bounded(argv[4]));std::filesystem::create_directories(out);
    std::int64_t step_ns=0;const auto started=std::chrono::steady_clock::now();
    if(mode=="baseline") {
      p::Recipe initial{id,p::read_bounded(argv[3]),{72000},{}};
      // Configuration validates canonical final pause, so supply the intended final
      // boundary for config decode, then start recording the actual admitted history.
      initial.admissions={{{72000},c::SessionControl{{{72000},"synthetic-session"},{81},"session.owner",c::PauseControl{true}}}};
      auto cfg=p::configuration(initial,root);initial.admissions.clear();Recording recorder(cfg,std::move(initial));identity_check(recorder.session,id);
      const auto axes=recorder.session.initialization().solved_controls;auto pulse=axes;pulse.roll=.001;
      recorder.input(p::Registration{"pilot.controls",c::Authority::pilot});recorder.input(command(cfg,axes,60000,1));recorder.input(command(cfg,pulse,121,2));
      std::string digest(64,'0');
      for(std::uint64_t boundary=0;boundary<72000;++boundary) {
        if(boundary==100) {recorder.input(lifecycle(cfg,boundary,77,c::PauseControl{true}));if(recorder.session.step_fixed().stepped)throw std::runtime_error("Pause failed");recorder.input(lifecycle(cfg,boundary,78,c::PauseControl{false}));recorder.input(lifecycle(cfg,boundary,79,c::TimeScaleControl{.5}));}
        if(boundary==121)recorder.input(command(cfg,axes,241,3));
        if(boundary==1000)recorder.input(p::Registration{"pilot.backup",c::Authority::pilot});
        if(boundary==20000) {recorder.input(command(cfg,pulse,72001,4));recorder.input(command(cfg,axes,20001,5));recorder.input(command(cfg,axes,72020,1,"pilot.backup"));}
        if(boundary==40000)recorder.input(lifecycle(cfg,boundary,80,c::TimeScaleControl{2}));
        const auto before=std::chrono::steady_clock::now();if(!recorder.session.step_fixed().stepped)throw std::runtime_error("Baseline unexpectedly paused");step_ns+=std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now()-before).count();digest=chain(digest,recorder.session);
      }
      recorder.input(lifecycle(cfg,72000,81,c::PauseControl{true}));const auto packet=p::encode(recorder.recipe);p::write_checked(out/"recipe.bin",packet);negative_tests(recorder.recipe,packet,root);
      text_file(out/"checkpoint.sha256",digest+'\n');text_file(out/"checkpoint.ndjson",f::transport::json(recorder.session.latest_snapshot())+'\n'+f::transport::json(recorder.session.latest_atmosphere())+'\n'+f::transport::json(recorder.session.diagnostics())+'\n');
      logs(recorder.recipe,recorder.session,out);
      text_file(out/"initialization.json",f::transport::json(recorder.session.initialization())+'\n');continuation(recorder.session,cfg,out);
    } else if(mode=="reconstruct") {
      const auto recipe=p::decode(p::read_bounded(argv[3]),id);auto cfg=p::configuration(recipe,root);f::Session session(cfg);identity_check(session,id);
      const auto digest=reconstruct_to_cut(session,recipe,step_ns);text_file(out/"checkpoint.sha256",digest+'\n');text_file(out/"checkpoint.ndjson",f::transport::json(session.latest_snapshot())+'\n'+f::transport::json(session.latest_atmosphere())+'\n'+f::transport::json(session.diagnostics())+'\n');
      logs(recipe,session,out);
      text_file(out/"initialization.json",f::transport::json(session.initialization())+'\n');continuation(session,cfg,out);
    } else throw std::invalid_argument("Unsupported proof mode");
    const auto elapsed=std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now()-started).count();
    text_file(out/"timing.json","{\"kind\":\"reconstruction-timing\",\"version\":1,\"cut_tick\":\"72000\",\"continuation_ticks\":\"7200\",\"replayed_step_ns\":"+std::to_string(step_ns)+",\"total_proof_ms\":"+std::to_string(elapsed)+",\"negative_cases\":"+std::to_string(rejects)+"}\n");
    std::cout<<"RECONSTRUCTION_PROOF_OK "<<mode<<'\n';return 0;
  } catch(const std::exception& error) {std::cerr<<"Reconstruction rejected/failed: "<<error.what()<<'\n';return 1;}
}
