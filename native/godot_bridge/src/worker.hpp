#pragma once
#include <flight/fdm/protocol.hpp>
#include <condition_variable>
#include <deque>
#include <functional>
#include <future>
#include <mutex>
#include <thread>

namespace flight::bridge {
struct Response {
  std::string initialization, aircraft, atmosphere;
  std::vector<std::string> commands, events;
  std::uint64_t delivered_sequence{};
  bool stepped{}, queued{};
  int rejection{};
};
class Worker final {
 public:
  explicit Worker(fdm::SessionConfig config);
  ~Worker();
  Worker(const Worker&) = delete;
  Worker& operator=(const Worker&) = delete;
  Response call(std::function<Response(fdm::Session&)> operation);
  void close() noexcept;
  static void close_all() noexcept;
 private:
  struct Request { std::function<Response(fdm::Session&)> operation; std::promise<Response> promise; };
  std::mutex mutex_; std::condition_variable condition_;
  std::deque<Request> pending_; bool closing_{};
  std::jthread thread_;
};
Response sample(fdm::Session& session);
}
