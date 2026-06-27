#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <shellapi.h>

#include <memory>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  void RegisterNativeMethodChannel();
  void ConfigureTray(bool close_to_tray, bool notifications_enabled);
  void EnsureTrayIcon();
  void RemoveTrayIcon();
  void RestoreFromTray();
  void ShowTrayMenu();
  void ShowNativeNotification(const std::wstring& title,
                              const std::wstring& body);

  static constexpr UINT kTrayCallbackMessage = WM_APP + 77;

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      native_channel_;

  bool close_to_tray_ = false;
  bool notifications_enabled_ = true;
  bool force_quit_ = false;
  bool tray_icon_added_ = false;
  HICON tray_icon_handle_ = nullptr;
  NOTIFYICONDATAW tray_icon_{};
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
