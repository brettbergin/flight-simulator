#include "interactive_worker.hpp"
#include <flight/fdm/protocol.hpp>
#include <set>
#include <stdexcept>
namespace flight::bridge {
namespace {std::mutex registry_mutex;std::set<InteractiveWorker*> workers;}
InteractiveReply interactive_sample(interactive::Session& session,const interactive::AnalyticSurface& surface) {
  InteractiveReply out;
  const auto aircraft=session.latest();const auto atmosphere=session.atmosphere();
  if(!interactive::c::valid(aircraft)||!interactive::c::valid(atmosphere)) throw std::runtime_error("Invalid interactive copied publication");
  out.aircraft=interactive::snapshot_json(aircraft);out.atmosphere=fdm::transport::json(atmosphere);
  out.held=session.held();out.live=session.live();out.paused=session.paused();out.time_scale=session.time_scale();out.fault=session.fault();
  out.status=!out.live?interactive::Status::discarded:out.paused?interactive::Status::paused:interactive::Status::completed;
  const auto ground=surface.sample({aircraft.header,aircraft.position});
  if(const auto* valid=std::get_if<interactive::c::ValidGround>(&ground.sample)) {
    out.ground_valid=true;out.surface_height_m=valid->surface_height_m;out.clearance_m=aircraft.position.ellipsoid_height_m-valid->surface_height_m;
  }
  return out;
}
InteractiveWorker::InteractiveWorker(interactive::Config config) {
  auto ready=std::make_shared<std::promise<void>>();auto initialized=ready->get_future();
  thread_=std::jthread([this,config=std::move(config),ready]() mutable {
    try {
      // Construction, every method, close and destruction stay on this owner.
      // Session itself registers the trusted pilot source; no Godot registration API.
      interactive::Session session(std::move(config));ready->set_value();
      for(;;) {
        Request request;
        {std::unique_lock lock(mutex_);condition_.wait(lock,[this]{return closing_||!pending_.empty();});
         if(closing_) {break;}
         request=std::move(pending_.front());pending_.pop_front();}
        try {request.promise.set_value(request.operation(session));}
        catch(...) {request.promise.set_exception(std::current_exception());}
      }
      session.close();
    } catch(...) {try {ready->set_exception(std::current_exception());}catch(...) {}}
  });
  try {initialized.get();}catch(...) {close();throw;}
  std::lock_guard lock(registry_mutex);workers.insert(this);
}
InteractiveWorker::~InteractiveWorker(){close();std::lock_guard lock(registry_mutex);workers.erase(this);}
InteractiveReply InteractiveWorker::call(std::function<InteractiveReply(interactive::Session&)> operation) {
  Request request{std::move(operation),{}};auto result=request.promise.get_future();
  {std::lock_guard lock(mutex_);if(closing_||!thread_.joinable())throw std::runtime_error("Interactive session closed");
   if(pending_.size()>=16) {throw std::runtime_error("Interactive synchronous mailbox full");}
   pending_.push_back(std::move(request));}
  condition_.notify_one();return result.get();
}
void InteractiveWorker::close() noexcept {
  {std::lock_guard lock(mutex_);closing_=true;
   for(auto& request:pending_){try {request.promise.set_exception(std::make_exception_ptr(std::runtime_error("Interactive session closed")));}catch(...) {}}
   pending_.clear();}
  condition_.notify_all();if(thread_.joinable())thread_.join();
}
void InteractiveWorker::close_all() noexcept {std::lock_guard lock(registry_mutex);for(auto* worker:workers)worker->close();}
}
