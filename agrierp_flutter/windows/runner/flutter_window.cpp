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
  // ⚠️ SANS CADRE SYSTEME, REDUIRE, AGRANDIR, DEPLACER ET FERMER DOIVENT VENIR
  // DE L'APPLICATION. Une dependance externe (`window_manager`) aurait exige
  // une recuperation de paquet ; ce canal de cinq methodes se suffit et
  // n'ajoute rien a installer sur un poste hors ligne.
  //
  //   reduire                  -> reduit dans la barre des taches.
  //   fermer                   -> WM_CLOSE (la confirmation est cote Dart).
  //   etat                     -> {agrandie, x, y, largeur, hauteur} : l'etat et
  //                               la ZONE DE TRAVAIL courante du moniteur.
  //   basculerAgrandissement   -> agrandit (zone de travail) ou restaure ;
  //                               rend le meme dictionnaire.
  //   deplacer                 -> demarre le deplacement a la souris (barre).
  //
  // ⚠️ « Agrandir » = occuper la ZONE DE TRAVAIL, jamais le moniteur entier :
  // la barre des taches de Windows reste visible (voir Win32Window).
  auto canal = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "agrierp/fenetre",
      &flutter::StandardMethodCodec::GetInstance());

  HWND fenetre = GetHandle();
  canal->SetMethodCallHandler(
      [this, fenetre](const auto& appel, auto resultat) {
        if (appel.method_name() == "reduire") {
          ::ShowWindow(fenetre, SW_MINIMIZE);
          resultat->Success();
        } else if (appel.method_name() == "fermer") {
          ::PostMessage(fenetre, WM_CLOSE, 0, 0);
          resultat->Success();
        } else if (appel.method_name() == "etat") {
          resultat->Success(EtatFenetre());
        } else if (appel.method_name() == "basculerAgrandissement") {
          ToggleMaximize();
          resultat->Success(EtatFenetre());
        } else if (appel.method_name() == "deplacer") {
          // Deplacement par la barre superieure. Une fenetre agrandie ne se
          // deplace pas (elle occupe la zone de travail) : le geste est sans
          // effet, comme la barre de titre d'une fenetre agrandie sans
          // restauration. Le message est POSTE (et non envoye) pour ne pas
          // bloquer ce rappel dans la boucle de deplacement du systeme.
          if (!IsMaximizedToWorkArea()) {
            POINT curseur{};
            ::GetCursorPos(&curseur);
            ::ReleaseCapture();
            ::PostMessage(fenetre, WM_NCLBUTTONDOWN, HTCAPTION,
                          MAKELPARAM(curseur.x, curseur.y));
          }
          resultat->Success();
        } else {
          resultat->NotImplemented();
        }
      });
  canal_fenetre_ = std::move(canal);

  flutter_controller_->engine()->SetNextFrameCallback([this]() {
    // AgriERP S'OUVRE AGRANDI, SUR LA ZONE DE TRAVAIL.
    //
    // La fenetre est creee CACHEE (sans `WS_VISIBLE`) et n'est montree qu'ici, a
    // la premiere image. L'agrandissement doit se faire au meme endroit que
    // l'affichage, pas avant : un `ShowWindow` place dans `main()` etait
    // ecrase par le `Show()` (SW_SHOWNORMAL) qui suivait.
    //
    // ⚠️ PAS `SW_SHOWMAXIMIZED` : sur une fenetre `WS_POPUP` (sans cadre), il
    // la fait couvrir TOUT le moniteur et MASQUE LA BARRE DES TACHES de Windows
    // (defaut constate chez le client). La fenetre est calee a la main sur la
    // zone de travail (`MaximizeToWorkArea`, `rcWork` du moniteur) ; la barre
    // des taches reste visible, quel que soit son cote ou sa taille.
    MaximizeToWorkArea();
    Show();
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

flutter::EncodableValue FlutterWindow::EtatFenetre() {
  const RECT zone = GetWorkArea();
  flutter::EncodableMap etat;
  etat[flutter::EncodableValue("agrandie")] =
      flutter::EncodableValue(IsMaximizedToWorkArea());
  etat[flutter::EncodableValue("x")] =
      flutter::EncodableValue(static_cast<int>(zone.left));
  etat[flutter::EncodableValue("y")] =
      flutter::EncodableValue(static_cast<int>(zone.top));
  etat[flutter::EncodableValue("largeur")] =
      flutter::EncodableValue(static_cast<int>(zone.right - zone.left));
  etat[flutter::EncodableValue("hauteur")] =
      flutter::EncodableValue(static_cast<int>(zone.bottom - zone.top));
  return flutter::EncodableValue(etat);
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // AgriERP : la zone de travail change (resolution, barre des taches). Le
  // message est observe, jamais consomme : Flutter le recoit ensuite.
  OnWorkAreaMessage(message, wparam);
  if (message == WM_GETMINMAXINFO) {
    FillMinMaxInfo(lparam);
    return 0;
  }

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
