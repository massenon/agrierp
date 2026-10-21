#include "win32_window.h"

#include <dwmapi.h>
#include <flutter_windows.h>

#include <algorithm>

#include "resource.h"

namespace {

/// Window attribute that enables dark mode window decorations.
///
/// Redefined in case the developer's machine has a Windows SDK older than
/// version 10.0.22000.0.
/// See: https://docs.microsoft.com/windows/win32/api/dwmapi/ne-dwmapi-dwmwindowattribute
#ifndef DWMWA_USE_IMMERSIVE_DARK_MODE
#define DWMWA_USE_IMMERSIVE_DARK_MODE 20
#endif

constexpr const wchar_t kWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";

/// Registry key for app theme preference.
///
/// A value of 0 indicates apps should use dark mode. A non-zero or missing
/// value indicates apps should use light mode.
constexpr const wchar_t kGetPreferredBrightnessRegKey[] =
  L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize";
constexpr const wchar_t kGetPreferredBrightnessRegValue[] = L"AppsUseLightTheme";

// The number of Win32Window objects that currently exist.
static int g_active_window_count = 0;

using EnableNonClientDpiScaling = BOOL __stdcall(HWND hwnd);

// Scale helper to convert logical scaler values to physical using passed in
// scale factor
int Scale(int source, double scale_factor) {
  return static_cast<int>(source * scale_factor);
}

// AgriERP : taille minimale de la fenetre, en pixels LOGIQUES (a 96 ppp). Elle
// reste sous le plus petit ecran courant meme a 150 % de mise a l'echelle ; elle
// est de toute facon plafonnee a la zone de travail (voir FillMinMaxInfo).
constexpr int kMinLogicalWidth = 640;
constexpr int kMinLogicalHeight = 480;

// AgriERP : l'icone de l'application (le logo de la ferme, ressource
// IDI_APP_ICON de Runner.rc) est donnee a la fenetre en GRANDE taille (Alt+Tab,
// barre des taches) et en PETITE taille (coin de la fenetre, barre des taches
// en mode compact). Sans cela, Windows redimensionne l'unique icone de la classe
// et la barre des taches la montre floue. LR_SHARED : le systeme gere la duree
// de vie, rien a detruire.
void ApplyWindowIcons(HWND hwnd) {
  HINSTANCE instance = GetModuleHandle(nullptr);
  HANDLE big = LoadImage(instance, MAKEINTRESOURCE(IDI_APP_ICON), IMAGE_ICON,
                         GetSystemMetrics(SM_CXICON),
                         GetSystemMetrics(SM_CYICON),
                         LR_DEFAULTCOLOR | LR_SHARED);
  HANDLE small_icon = LoadImage(instance, MAKEINTRESOURCE(IDI_APP_ICON),
                                IMAGE_ICON, GetSystemMetrics(SM_CXSMICON),
                                GetSystemMetrics(SM_CYSMICON),
                                LR_DEFAULTCOLOR | LR_SHARED);
  if (big) {
    SendMessage(hwnd, WM_SETICON, ICON_BIG, reinterpret_cast<LPARAM>(big));
  }
  if (small_icon) {
    SendMessage(hwnd, WM_SETICON, ICON_SMALL,
                reinterpret_cast<LPARAM>(small_icon));
  }
}

// Dynamically loads the |EnableNonClientDpiScaling| from the User32 module.
// This API is only needed for PerMonitor V1 awareness mode.
void EnableFullDpiSupportIfAvailable(HWND hwnd) {
  HMODULE user32_module = LoadLibraryA("User32.dll");
  if (!user32_module) {
    return;
  }
  auto enable_non_client_dpi_scaling =
      reinterpret_cast<EnableNonClientDpiScaling*>(
          GetProcAddress(user32_module, "EnableNonClientDpiScaling"));
  if (enable_non_client_dpi_scaling != nullptr) {
    enable_non_client_dpi_scaling(hwnd);
  }
  FreeLibrary(user32_module);
}

}  // namespace

// Manages the Win32Window's window class registration.
class WindowClassRegistrar {
 public:
  ~WindowClassRegistrar() = default;

  // Returns the singleton registrar instance.
  static WindowClassRegistrar* GetInstance() {
    if (!instance_) {
      instance_ = new WindowClassRegistrar();
    }
    return instance_;
  }

  // Returns the name of the window class, registering the class if it hasn't
  // previously been registered.
  const wchar_t* GetWindowClass();

  // Unregisters the window class. Should only be called if there are no
  // instances of the window.
  void UnregisterWindowClass();

 private:
  WindowClassRegistrar() = default;

  static WindowClassRegistrar* instance_;

  bool class_registered_ = false;
};

WindowClassRegistrar* WindowClassRegistrar::instance_ = nullptr;

const wchar_t* WindowClassRegistrar::GetWindowClass() {
  if (!class_registered_) {
    WNDCLASSEX window_class{};
    window_class.cbSize = sizeof(WNDCLASSEX);
    window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
    window_class.lpszClassName = kWindowClassName;
    window_class.style = CS_HREDRAW | CS_VREDRAW;
    window_class.cbClsExtra = 0;
    window_class.cbWndExtra = 0;
    window_class.hInstance = GetModuleHandle(nullptr);
    window_class.hIcon =
        LoadIcon(window_class.hInstance, MAKEINTRESOURCE(IDI_APP_ICON));
    // Petite icone de la classe : meme ressource, a la taille « petite » du systeme.
    window_class.hIconSm = static_cast<HICON>(LoadImage(
        window_class.hInstance, MAKEINTRESOURCE(IDI_APP_ICON), IMAGE_ICON,
        GetSystemMetrics(SM_CXSMICON), GetSystemMetrics(SM_CYSMICON),
        LR_DEFAULTCOLOR | LR_SHARED));
    window_class.hbrBackground = 0;
    window_class.lpszMenuName = nullptr;
    window_class.lpfnWndProc = Win32Window::WndProc;
    RegisterClassEx(&window_class);
    class_registered_ = true;
  }
  return kWindowClassName;
}

void WindowClassRegistrar::UnregisterWindowClass() {
  UnregisterClass(kWindowClassName, nullptr);
  class_registered_ = false;
}

Win32Window::Win32Window() {
  ++g_active_window_count;
}

Win32Window::~Win32Window() {
  --g_active_window_count;
  Destroy();
}

bool Win32Window::Create(const std::wstring& title,
                         const Point& origin,
                         const Size& size) {
  Destroy();

  const wchar_t* window_class =
      WindowClassRegistrar::GetInstance()->GetWindowClass();

  const POINT target_point = {static_cast<LONG>(origin.x),
                              static_cast<LONG>(origin.y)};
  HMONITOR monitor = MonitorFromPoint(target_point, MONITOR_DEFAULTTONEAREST);
  UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
  double scale_factor = dpi / 96.0;

  // AgriERP s'affiche SANS CADRE SYSTEME.
  //
  // `WS_POPUP` retire la barre de titre et ses trois boutons. L'ecran occupe
  // ainsi toute la surface, comme la maquette qui est une page pleine.
  //
  // ⚠️ CONSEQUENCE ASSUMEE, ET COMPENSEE : sans barre de titre, l'utilisateur
  // n'a plus aucun moyen de reduire ni de fermer l'application. Les deux
  // commandes sont donc rendues dans la barre superieure de l'application
  // elle-meme (voir `BarreSuperieure`), via le canal `agrierp/fenetre`. Les
  // retirer sans les remplacer aurait enferme l'utilisateur.
  HWND window = CreateWindow(
      window_class, title.c_str(), WS_POPUP,
      Scale(origin.x, scale_factor), Scale(origin.y, scale_factor),
      Scale(size.width, scale_factor), Scale(size.height, scale_factor),
      nullptr, nullptr, GetModuleHandle(nullptr), this);

  if (!window) {
    return false;
  }

  UpdateTheme(window);
  ApplyWindowIcons(window);

  return OnCreate();
}

bool Win32Window::Show() {
  return ShowWindow(window_handle_, SW_SHOWNORMAL);
}

// static
LRESULT CALLBACK Win32Window::WndProc(HWND const window,
                                      UINT const message,
                                      WPARAM const wparam,
                                      LPARAM const lparam) noexcept {
  if (message == WM_NCCREATE) {
    auto window_struct = reinterpret_cast<CREATESTRUCT*>(lparam);
    SetWindowLongPtr(window, GWLP_USERDATA,
                     reinterpret_cast<LONG_PTR>(window_struct->lpCreateParams));

    auto that = static_cast<Win32Window*>(window_struct->lpCreateParams);
    EnableFullDpiSupportIfAvailable(window);
    that->window_handle_ = window;
  } else if (Win32Window* that = GetThisFromHandle(window)) {
    return that->MessageHandler(window, message, wparam, lparam);
  }

  return DefWindowProc(window, message, wparam, lparam);
}

LRESULT
Win32Window::MessageHandler(HWND hwnd,
                            UINT const message,
                            WPARAM const wparam,
                            LPARAM const lparam) noexcept {
  switch (message) {
    case WM_DESTROY:
      window_handle_ = nullptr;
      Destroy();
      if (quit_on_close_) {
        PostQuitMessage(0);
      }
      return 0;

    case WM_DPICHANGED: {
      auto newRectSize = reinterpret_cast<RECT*>(lparam);
      LONG newWidth = newRectSize->right - newRectSize->left;
      LONG newHeight = newRectSize->bottom - newRectSize->top;

      SetWindowPos(hwnd, nullptr, newRectSize->left, newRectSize->top, newWidth,
                   newHeight, SWP_NOZORDER | SWP_NOACTIVATE);

      // AgriERP : une fenetre agrandie reste sur la zone de travail du
      // moniteur qui la porte desormais (autre resolution, autre echelle, autre
      // barre des taches). Le rectangle suggere ci-dessus l'a d'abord amenee
      // sur ce moniteur ; on la cale ensuite sur SA zone de travail.
      if (maximized_) {
        FitToWorkArea();
      }

      return 0;
    }
    case WM_SIZE: {
      // AgriERP : sortie de reduction dans la barre des taches. Si la zone de
      // travail a change pendant que la fenetre etait reduite, elle se recale.
      if (maximized_ && wparam == SIZE_RESTORED) {
        FitToWorkArea();
      }
      RECT rect = GetClientArea();
      if (child_content_ != nullptr) {
        // Size and position the child window.
        MoveWindow(child_content_, rect.left, rect.top, rect.right - rect.left,
                   rect.bottom - rect.top, TRUE);
      }
      return 0;
    }

    case WM_ACTIVATE:
      if (child_content_ != nullptr) {
        SetFocus(child_content_);
      }
      return 0;

    case WM_DWMCOLORIZATIONCOLORCHANGED:
      UpdateTheme(hwnd);
      return 0;
  }

  return DefWindowProc(window_handle_, message, wparam, lparam);
}

void Win32Window::Destroy() {
  OnDestroy();

  if (window_handle_) {
    DestroyWindow(window_handle_);
    window_handle_ = nullptr;
  }
  if (g_active_window_count == 0) {
    WindowClassRegistrar::GetInstance()->UnregisterWindowClass();
  }
}

Win32Window* Win32Window::GetThisFromHandle(HWND const window) noexcept {
  return reinterpret_cast<Win32Window*>(
      GetWindowLongPtr(window, GWLP_USERDATA));
}

void Win32Window::SetChildContent(HWND content) {
  child_content_ = content;
  SetParent(content, window_handle_);
  RECT frame = GetClientArea();

  MoveWindow(content, frame.left, frame.top, frame.right - frame.left,
             frame.bottom - frame.top, true);

  SetFocus(child_content_);
}

RECT Win32Window::GetClientArea() {
  RECT frame;
  GetClientRect(window_handle_, &frame);
  return frame;
}

HWND Win32Window::GetHandle() {
  return window_handle_;
}

void Win32Window::SetQuitOnClose(bool quit_on_close) {
  quit_on_close_ = quit_on_close;
}

RECT Win32Window::GetWorkArea() const {
  // Repli si le systeme ne repond pas : un ecran de bureau courant.
  RECT work = {0, 0, 1280, 720};

  // `rcWork` = le moniteur MOINS la barre des taches (et les barres d'outils
  // ancrees), quel que soit leur cote ou leur taille. Le moniteur est celui qui
  // porte la fenetre ; MONITOR_DEFAULTTONEAREST garantit une reponse meme si la
  // fenetre est hors de tout moniteur (debranchement a chaud).
  HMONITOR monitor = nullptr;
  if (window_handle_) {
    monitor = MonitorFromWindow(window_handle_, MONITOR_DEFAULTTONEAREST);
  }
  MONITORINFO info{};
  info.cbSize = sizeof(MONITORINFO);
  if (monitor && GetMonitorInfo(monitor, &info)) {
    work = info.rcWork;
  } else {
    RECT spi{};
    if (SystemParametersInfo(SPI_GETWORKAREA, 0, &spi, 0)) {
      work = spi;
    }
  }
  return work;
}

bool Win32Window::IsMaximizedToWorkArea() const {
  return maximized_;
}

void Win32Window::FitToWorkArea() {
  if (!window_handle_ || IsIconic(window_handle_)) {
    return;
  }
  RECT work = GetWorkArea();
  RECT actuel{};
  GetWindowRect(window_handle_, &actuel);
  if (actuel.left == work.left && actuel.top == work.top &&
      actuel.right == work.right && actuel.bottom == work.bottom) {
    return;
  }
  SetWindowPos(window_handle_, nullptr, work.left, work.top,
               work.right - work.left, work.bottom - work.top,
               SWP_NOZORDER | SWP_NOACTIVATE);
}

void Win32Window::MaximizeToWorkArea() {
  if (!window_handle_) {
    return;
  }
  if (!maximized_) {
    // Position de restauration : celle de la fenetre AVANT l'agrandissement.
    GetWindowRect(window_handle_, &restore_rect_);
  }
  maximized_ = true;
  FitToWorkArea();
}

void Win32Window::RestoreFromMaximized() {
  if (!window_handle_ || !maximized_) {
    return;
  }
  maximized_ = false;

  // La position memorisee peut ne plus tenir : autre moniteur, resolution
  // reduite, barre des taches agrandie. Elle est ramenee DANS la zone de travail.
  RECT work = GetWorkArea();
  const LONG work_width = work.right - work.left;
  const LONG work_height = work.bottom - work.top;
  LONG width = restore_rect_.right - restore_rect_.left;
  LONG height = restore_rect_.bottom - restore_rect_.top;
  if (width <= 0 || height <= 0) {
    // Jamais memorisee (agrandie des l'ouverture) : 80 % de la zone de travail.
    width = work_width * 8 / 10;
    height = work_height * 8 / 10;
  }
  width = std::min(width, work_width);
  height = std::min(height, work_height);
  LONG left = std::max(work.left, std::min(restore_rect_.left, work.right - width));
  LONG top = std::max(work.top, std::min(restore_rect_.top, work.bottom - height));
  SetWindowPos(window_handle_, nullptr, left, top, width, height,
               SWP_NOZORDER | SWP_NOACTIVATE);
}

bool Win32Window::ToggleMaximize() {
  if (maximized_) {
    RestoreFromMaximized();
  } else {
    MaximizeToWorkArea();
  }
  return maximized_;
}

void Win32Window::OnWorkAreaMessage(UINT const message, WPARAM const wparam) {
  const bool zone_changee =
      message == WM_DISPLAYCHANGE ||
      (message == WM_SETTINGCHANGE && wparam == SPI_SETWORKAREA);
  if (zone_changee && maximized_) {
    FitToWorkArea();
  }
}

void Win32Window::FillMinMaxInfo(LPARAM const lparam) const {
  auto* info = reinterpret_cast<MINMAXINFO*>(lparam);
  if (!info || !window_handle_) {
    return;
  }
  HMONITOR monitor =
      MonitorFromWindow(window_handle_, MONITOR_DEFAULTTONEAREST);
  MONITORINFO moniteur{};
  moniteur.cbSize = sizeof(MONITORINFO);
  if (!monitor || !GetMonitorInfo(monitor, &moniteur)) {
    return;
  }
  const RECT& work = moniteur.rcWork;
  const RECT& full = moniteur.rcMonitor;

  // Un agrandissement fait par le systeme (touche Windows, menu de la barre
  // des taches) reste lui aussi dans la zone de travail. ptMaxPosition est
  // relatif au coin du moniteur.
  info->ptMaxPosition.x = work.left - full.left;
  info->ptMaxPosition.y = work.top - full.top;
  info->ptMaxSize.x = work.right - work.left;
  info->ptMaxSize.y = work.bottom - work.top;

  // Taille minimale a l'echelle du moniteur, jamais plus grande que la zone de
  // travail (sinon la fenetre deborderait d'un petit ecran).
  const double scale = FlutterDesktopGetDpiForHWND(window_handle_) / 96.0;
  info->ptMinTrackSize.x = std::min(Scale(kMinLogicalWidth, scale),
                                    static_cast<int>(info->ptMaxSize.x));
  info->ptMinTrackSize.y = std::min(Scale(kMinLogicalHeight, scale),
                                    static_cast<int>(info->ptMaxSize.y));
}

bool Win32Window::OnCreate() {
  // No-op; provided for subclasses.
  return true;
}

void Win32Window::OnDestroy() {
  // No-op; provided for subclasses.
}

void Win32Window::UpdateTheme(HWND const window) {
  DWORD light_mode;
  DWORD light_mode_size = sizeof(light_mode);
  LSTATUS result = RegGetValue(HKEY_CURRENT_USER, kGetPreferredBrightnessRegKey,
                               kGetPreferredBrightnessRegValue,
                               RRF_RT_REG_DWORD, nullptr, &light_mode,
                               &light_mode_size);

  if (result == ERROR_SUCCESS) {
    BOOL enable_dark_mode = light_mode == 0;
    DwmSetWindowAttribute(window, DWMWA_USE_IMMERSIVE_DARK_MODE,
                          &enable_dark_mode, sizeof(enable_dark_mode));
  }
}
