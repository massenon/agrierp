#include "flutter_window.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <optional>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

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
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  // Canal minimal de commande de la fenetre.
  //
  // ⚠️ SANS CADRE SYSTEME, REDUIRE ET FERMER DOIVENT VENIR DE L'APPLICATION.
  // Une dependance externe (`window_manager`) aurait exige une recuperation de
  // paquet ; ce canal de deux methodes se suffit et n'ajoute rien a installer
  // sur un poste hors ligne.
  auto canal = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "agrierp/fenetre",
      &flutter::StandardMethodCodec::GetInstance());

  HWND fenetre = GetHandle();
  canal->SetMethodCallHandler(
      [fenetre](const auto& appel, auto resultat) {
        if (appel.method_name() == "reduire") {
          ::ShowWindow(fenetre, SW_MINIMIZE);
          resultat->Success();
        } else if (appel.method_name() == "fermer") {
          ::PostMessage(fenetre, WM_CLOSE, 0, 0);
          resultat->Success();
        } else {
          resultat->NotImplemented();
        }
      });
  canal_fenetre_ = std::move(canal);

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    // AgriERP S'OUVRE MAXIMISE.
    //
    // La fenetre est creee CACHEE (`WS_OVERLAPPEDWINDOW` sans `WS_VISIBLE`) et
    // n'est montree qu'ici, a la premiere image. Maximiser depuis `main()`
    // apres `Create()` ne servait donc a rien : ce `Show()` (SW_SHOWNORMAL)
    // s'executait APRES et ramenait la fenetre a 1280x720. La maximisation
    // doit se faire au meme endroit que l'affichage, pas avant.
    //
    // Maximise, PAS plein ecran sans bordure : le poste est un ordinateur
    // partage, ou l'on bascule vers un navigateur ou l'explorateur. Supprimer
    // la barre de titre priverait l'utilisateur du bouton de reduction.
    ::ShowWindow(GetHandle(), SW_SHOWMAXIMIZED);
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
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
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
