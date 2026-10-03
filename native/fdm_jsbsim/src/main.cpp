#include <flight/fdm/protocol.hpp>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <algorithm>
#include <chrono>
int main(int argc,char** argv) {
  try {
    if(argc!=4) throw std::invalid_argument("Usage: fdm_harness <model-root> <bounded-request.bin> <output.ndjson>");
    const auto size=std::filesystem::file_size(argv[2]); if(size>4*1024*1024) throw std::invalid_argument("Request too large");
    std::vector<std::uint8_t> bytes(static_cast<std::size_t>(size)); std::ifstream input(argv[2],std::ios::binary);
    input.read(reinterpret_cast<char*>(bytes.data()),static_cast<std::streamsize>(bytes.size())); if(!input) throw std::runtime_error("Request read failed");
    auto request=flight::fdm::transport::decode(bytes,argv[1]); flight::fdm::Session session(std::move(request.config));
    if(!session.register_host_source("pilot.controls",flight::contracts::v1::Authority::pilot)) throw std::runtime_error("Source registration failed");
    for(auto& command:request.commands) if(!session.submit(command).queued) throw std::invalid_argument("Command submission rejected");
    std::ofstream output(argv[3],std::ios::binary|std::ios::trunc); if(!output) throw std::runtime_error("Output open failed");
    output<<flight::fdm::transport::json(session.initialization())<<'\n'<<flight::fdm::transport::json(session.latest_snapshot())<<'\n'<<flight::fdm::transport::json(session.diagnostics())<<'\n';
    std::vector<std::int64_t> timing_ns; timing_ns.reserve(static_cast<std::size_t>(request.duration_ticks));
    for(std::uint64_t i=1;i<=request.duration_ticks;++i) {
      const auto started=std::chrono::steady_clock::now(); const auto result=session.step_fixed();
      timing_ns.push_back(std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now()-started).count());
      if(!result.stepped) throw std::runtime_error("Unexpected paused harness");
      for(const auto& command:result.applied_commands) output<<flight::fdm::transport::json(command)<<'\n';
      if(i%request.sample_interval_ticks==0 || i==request.duration_ticks) output<<flight::fdm::transport::json(result.aircraft)<<'\n'<<flight::fdm::transport::json(result.atmosphere)<<'\n'<<flight::fdm::transport::json(session.diagnostics())<<'\n';
      if(!output) throw std::runtime_error("Output write failed");
    }
    output.close();
    if(!output) throw std::runtime_error("Output close failed");
    std::sort(timing_ns.begin(),timing_ns.end()); std::ofstream timing(std::string(argv[3])+".timing.json",std::ios::binary|std::ios::trunc);
    timing<<"{\"kind\":\"fdm-performance\",\"version\":1,\"steps\":"<<timing_ns.size()<<",\"step_scope\":\"session.step_fixed-no-output-serialization\",\"p50_ns\":"<<timing_ns[(timing_ns.size()-1)/2]
      <<",\"p99_ns\":"<<timing_ns[(timing_ns.size()*99+99)/100-1]<<",\"max_ns\":"<<timing_ns.back()<<"}\n";
    timing.close(); if(!timing) throw std::runtime_error("Timing write failed");
    session.close(); return 0;
  } catch(const std::exception& error) { std::cerr<<"FDM harness rejected/failed: "<<error.what()<<'\n'; return 1; }
}
