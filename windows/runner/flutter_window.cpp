#include "flutter_window.h"

#include <flutter/standard_method_codec.h>
#include <windows.h>

#include <cwchar>
#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "resource.h"

namespace {

std::wstring Utf8ToWide(const std::string& value) {
  if (value.empty()) {
    return std::wstring();
  }
  int size = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.c_str(),
                                 static_cast<int>(value.size()), nullptr, 0);
  if (size <= 0) {
    size = MultiByteToWideChar(CP_ACP, 0, value.c_str(),
                               static_cast<int>(value.size()), nullptr, 0);
    if (size <= 0) {
      return std::wstring(value.begin(), value.end());
    }
    std::wstring result(size, L'\0');
    MultiByteToWideChar(CP_ACP, 0, value.c_str(),
                        static_cast<int>(value.size()), result.data(), size);
    return result;
  }
  std::wstring result(size, L'\0');
  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.c_str(),
                      static_cast<int>(value.size()), result.data(), size);
  return result;
}

const flutter::EncodableValue* FindArg(const flutter::EncodableMap& args,
                                       const char* name) {
  auto it = args.find(flutter::EncodableValue(std::string(name)));
  return it == args.end() ? nullptr : &it->second;
}

bool BoolArg(const flutter::EncodableMap& args, const char* name,
             bool fallback) {
  const auto* value = FindArg(args, name);
  if (!value) {
    return fallback;
  }
  if (const auto* typed = std::get_if<bool>(value)) {
    return *typed;
  }
  return fallback;
}

std::wstring StringArg(const flutter::EncodableMap& args, const char* name,
                       const wchar_t* fallback) {
  const auto* value = FindArg(args, name);
  if (!value) {
    return fallback;
  }
  if (const auto* typed = std::get_if<std::string>(value)) {
    return Utf8ToWide(*typed);
  }
  return fallback;
}

template <size_t N>
void CopyWide(wchar_t (&dest)[N], const std::wstring& value) {
  wcsncpy_s(dest, value.c_str(), _TRUNCATE);
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() { RemoveTrayIcon(); }

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  RegisterNativeMethodChannel();
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  RemoveTrayIcon();
  if (flutter_controller_) {
    native_channel_ = nullptr;
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

void FlutterWindow::RegisterNativeMethodChannel() {
  native_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "ai_agent/windows",
          &flutter::StandardMethodCodec::GetInstance());

  native_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<
                 flutter::MethodResult<flutter::EncodableValue>> result) {
        const auto* args_value = call.arguments();
        const auto* args =
            args_value ? std::get_if<flutter::EncodableMap>(args_value)
                       : nullptr;

        if (call.method_name() == "configureTray") {
          ConfigureTray(args ? BoolArg(*args, "closeToTray", false) : false,
                        args ? BoolArg(*args, "notifications", true) : true);
          result->Success(flutter::EncodableValue(true));
          return;
        }

        if (call.method_name() == "showNotification") {
          ShowNativeNotification(
              args ? StringArg(*args, "title", L"AI Agent") : L"AI Agent",
              args ? StringArg(*args, "body", L"") : L"");
          result->Success(flutter::EncodableValue(true));
          return;
        }

        result->NotImplemented();
      });
}

void FlutterWindow::ConfigureTray(bool close_to_tray,
                                  bool notifications_enabled) {
  close_to_tray_ = close_to_tray;
  notifications_enabled_ = notifications_enabled;
  if (close_to_tray_ || notifications_enabled_) {
    EnsureTrayIcon();
  } else {
    RemoveTrayIcon();
  }
}

void FlutterWindow::EnsureTrayIcon() {
  if (tray_icon_added_) {
    return;
  }
  HWND hwnd = GetHandle();
  if (!hwnd) {
    return;
  }

  ZeroMemory(&tray_icon_, sizeof(tray_icon_));
  tray_icon_.cbSize = sizeof(NOTIFYICONDATAW);
  tray_icon_.hWnd = hwnd;
  tray_icon_.uID = 1;
  tray_icon_.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
  tray_icon_.uCallbackMessage = kTrayCallbackMessage;
  tray_icon_handle_ = reinterpret_cast<HICON>(
      LoadImage(GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_APP_ICON),
                IMAGE_ICON, GetSystemMetrics(SM_CXSMICON),
                GetSystemMetrics(SM_CYSMICON), LR_DEFAULTCOLOR));
  if (!tray_icon_handle_) {
    tray_icon_handle_ =
        LoadIcon(GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_APP_ICON));
  }
  tray_icon_.hIcon = tray_icon_handle_;
  CopyWide(tray_icon_.szTip, L"AI Agent");

  tray_icon_added_ = Shell_NotifyIconW(NIM_ADD, &tray_icon_) == TRUE;
  if (tray_icon_added_) {
    tray_icon_.uVersion = NOTIFYICON_VERSION_4;
    Shell_NotifyIconW(NIM_SETVERSION, &tray_icon_);
  }
}

void FlutterWindow::RemoveTrayIcon() {
  if (tray_icon_added_) {
    Shell_NotifyIconW(NIM_DELETE, &tray_icon_);
    tray_icon_added_ = false;
  }
  if (tray_icon_handle_) {
    DestroyIcon(tray_icon_handle_);
    tray_icon_handle_ = nullptr;
  }
  ZeroMemory(&tray_icon_, sizeof(tray_icon_));
}

void FlutterWindow::RestoreFromTray() {
  HWND hwnd = GetHandle();
  if (!hwnd) {
    return;
  }
  ShowWindow(hwnd, SW_SHOW);
  ShowWindow(hwnd, SW_RESTORE);
  SetForegroundWindow(hwnd);
}

void FlutterWindow::ShowTrayMenu() {
  HWND hwnd = GetHandle();
  if (!hwnd) {
    return;
  }
  POINT cursor{};
  GetCursorPos(&cursor);
  HMENU menu = CreatePopupMenu();
  if (!menu) {
    return;
  }
  AppendMenuW(menu, MF_STRING, 1001, L"Развернуть");
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, 1002, L"Выход");
  SetForegroundWindow(hwnd);
  const UINT command = TrackPopupMenu(
      menu, TPM_RETURNCMD | TPM_NONOTIFY | TPM_RIGHTBUTTON, cursor.x, cursor.y,
      0, hwnd, nullptr);
  DestroyMenu(menu);
  if (command == 1001) {
    RestoreFromTray();
  } else if (command == 1002) {
    force_quit_ = true;
    RemoveTrayIcon();
    Destroy();
  }
}

void FlutterWindow::ShowNativeNotification(const std::wstring& title,
                                           const std::wstring& body) {
  if (!notifications_enabled_) {
    return;
  }
  EnsureTrayIcon();
  if (!tray_icon_added_) {
    return;
  }
  tray_icon_.uFlags = NIF_INFO;
  CopyWide(tray_icon_.szInfoTitle, title.empty() ? L"AI Agent" : title);
  CopyWide(tray_icon_.szInfo, body);
  tray_icon_.dwInfoFlags = NIIF_INFO;
  Shell_NotifyIconW(NIM_MODIFY, &tray_icon_);
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_CLOSE:
      if (close_to_tray_ && !force_quit_) {
        EnsureTrayIcon();
        ShowWindow(hwnd, SW_HIDE);
        return 0;
      }
      break;
    case kTrayCallbackMessage: {
      const auto event = static_cast<UINT>(lparam);
      if (event == WM_LBUTTONUP || event == WM_LBUTTONDBLCLK ||
          event == NIN_SELECT || event == NIN_KEYSELECT ||
          event == NIN_BALLOONUSERCLICK) {
        RestoreFromTray();
      } else if (event == WM_RBUTTONUP || event == WM_CONTEXTMENU) {
        ShowTrayMenu();
      }
      return 0;
    }
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
