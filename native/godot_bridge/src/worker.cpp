#include "worker.hpp"
#include <set>
#include <stdexcept>
namespace flight::bridge {
namespace {
std::mutex registry_mutex;
std::set<Worker*> workers;
}
Response sample(fdm::Session& session) {
  Response out;
  const auto aircraft=session.latest_snapshot();
  const auto atmosphere=session.latest_atmosphere();
  if(!fdm::c::valid(aircraft)||!fdm::c::valid(atmosphere)) throw std::runtime_error("Invalid authoritative native sample");
  out.aircraft=fdm::transport::json(aircraft); out.atmosphere=fdm::transport::json(atmosphere);
  return out;
}
Worker::Worker(fdm::SessionConfig config) {
  auto ready=std::make_shared<std::promise<void>>();
  auto initialized=ready->get_future();
  thread_=std::jthread([this,config=std::move(config),ready]() mutable {
    try {
      fdm::Session session(std::move(config));
      if(!session.register_host_source("pilot.controls",fdm::c::Authority::pilot)) throw std::runtime_error("Host source registration failed");
      ready->set_value();
      for(;;) {
        Request request;
        {
          std::unique_lock lock(mutex_);
          condition_.wait(lock,[this]{return closing_||!pending_.empty();});
          if(closing_) break;
          request=std::move(pending_.front()); pending_.pop_front();
        }
        try { request.promise.set_value(request.operation(session)); }
        catch(...) { request.promise.set_exception(std::current_exception()); }
      }
      session.close(); // Created, used and destroyed exclusively on this worker.
    } catch(...) {
      try { ready->set_exception(std::current_exception()); } catch(...) {}
    }
  });
  try { initialized.get(); }
  catch(...) { close(); throw; }
  std::lock_guard lock(registry_mutex); workers.insert(this);
}
Worker::~Worker() {
  close();
  std::lock_guard lock(registry_mutex); workers.erase(this);
}
Response Worker::call(std::function<Response(fdm::Session&)> operation) {
  Request request{std::move(operation),{}}; auto result=request.promise.get_future();
  {
    std::lock_guard lock(mutex_);
    if(closing_||!thread_.joinable()) throw std::runtime_error("Session closed");
    if(pending_.size()>=16) throw std::runtime_error("Bridge mailbox capacity");
    pending_.push_back(std::move(request));
  }
  condition_.notify_one();
  return result.get(); // Bounded requests; external smoke watchdog detects a vendor hang.
}
void Worker::close() noexcept {
  {
    std::lock_guard lock(mutex_); closing_=true;
    for(auto& request:pending_) {
      try { request.promise.set_exception(std::make_exception_ptr(std::runtime_error("Session closed"))); } catch(...) {}
    }
    pending_.clear();
  }
  condition_.notify_all();
  if(thread_.joinable()) thread_.join();
}
void Worker::close_all() noexcept {
  std::lock_guard lock(registry_mutex);
  for(auto* worker:workers) worker->close();
}
}
