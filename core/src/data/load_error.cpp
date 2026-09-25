#include "data/load_error.h"

namespace wm {

std::string LoadError::message() const {
  std::string m = file.empty() ? std::string("<memory>") : file;
  if (!path.empty()) m += ": " + path;
  m += ": " + reason;
  return m;
}

bool ErrorSink::fail(std::string_view path, std::string_view reason) {
  if (ok_) {
    ok_ = false;
    err_.path = std::string(path);
    err_.reason = std::string(reason);
  }
  return false;
}

std::string path_key(std::string_view path, std::string_view key) {
  std::string p(path);
  p += '.';
  p += key;
  return p;
}

std::string path_index(std::string_view path, std::size_t index) {
  std::string p(path);
  p += '[';
  p += std::to_string(index);
  p += ']';
  return p;
}

}  // namespace wm
