// Load errors (data_format.md §1): the file, the JSON path and the reason. The core never runs with partly
// valid data, so a loader stops at the first error.
#pragma once

#include <string>
#include <string_view>

namespace wm {

struct LoadError {
  std::string file;
  std::string path;    // JSON path, "$" is the document root, e.g. "$.configs[1].polar.values[17]"
  std::string reason;

  std::string message() const;  // "file: path: reason"
};

// First-error collector shared by the loaders.
class ErrorSink {
 public:
  ErrorSink(LoadError& err, std::string_view file) : err_(err) { err_.file = std::string(file); }

  // Records the first failure; always returns false so callers can `return sink.fail(...)`.
  bool fail(std::string_view path, std::string_view reason);
  bool ok() const { return ok_; }

 private:
  LoadError& err_;
  bool ok_ = true;
};

std::string path_key(std::string_view path, std::string_view key);    // path.key
std::string path_index(std::string_view path, std::size_t index);     // path[index]

}  // namespace wm
