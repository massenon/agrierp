#ifndef RUNNER_WIN32_WINDOW_H_
#define RUNNER_WIN32_WINDOW_H_

#include <windows.h>

#include <functional>
#include <memory>
#include <string>

// A class abstraction for a high DPI-aware Win32 Window. Intended to be
// inherited from by classes that wish to specialize with custom
// rendering and input handling
class Win32Window {
 public:
  struct Point {
    unsigned int x;
    unsigned int y;
    Point(unsigned int x, unsigned int y) : x(x), y(y) {}
  };

  struct Size {
    unsigned int width;
    unsigned int height;
    Size(unsigned int width, unsigned int height)
        : width(width), height(height) {}
  };

  Win32Window();
  virtual ~Win32Window();

  // Creates a win32 window with |title| that is positioned and sized using
  // |origin| and |size|. New windows are created on the default monitor. Window
  // sizes are specified to the OS in physical pixels, hence to ensure a
  // consistent size this function will scale the inputted width and height as
  // as appropriate for the default monitor. The window is invisible until
  // |Show| is called. Returns true if the window was created successfully.
  bool Create(const std::wstring& title, const Point& origin, const Size& size);

  // Show the current window. Returns true if the window was successfully shown.
  bool Show();

  // Release OS resources associated with window.
  void Destroy();

  // Inserts |content| into the window tree.
  void SetChildContent(HWND content);

  // Returns the backing Window handle to enable clients to set icon and other
  // window properties. Returns nullptr if the window has been destroyed.
  HWND GetHandle();

  // If true, closing this window will quit the application.
  void SetQuitOnClose(bool quit_on_close);

  // Return a RECT representing the bounds of the current client area.
  RECT GetClientArea();

  // ---- AgriERP : fenetre sans cadre qui respecte la barre des taches ----------
  //
  // La fenetre est un `WS_POPUP`. Un `ShowWindow(SW_SHOWMAXIMIZED)` sur un
  // popup le fait couvrir TOUT le moniteur, barre des taches comprise. Ces
  // methodes placent donc la fenetre elles-memes sur la ZONE DE TRAVAIL du
  // moniteur qui la porte (`rcWork` : le moniteur moins la barre des taches,
  // quel que soit son cote ou sa taille).

  // Zone de travail (coordonnees ecran, pixels physiques) du moniteur qui porte
  // la fenetre, ou du moniteur principal a defaut.
  RECT GetWorkArea() const;

  // Vrai tant que la fenetre est « agrandie » (calee sur la zone de travail).
  bool IsMaximizedToWorkArea() const;

  // Cale la fenetre sur la zone de travail ; memorise la position de restauration.
  void MaximizeToWorkArea();

  // Ramene la fenetre a sa position et sa taille de restauration, ramenees dans
  // la zone de travail si le moniteur ou la resolution ont change entre-temps.
  void RestoreFromMaximized();

  // Agrandit si la fenetre est restauree, restaure sinon. Rend le nouvel etat.
  bool ToggleMaximize();

 protected:
  // Processes and route salient window messages for mouse handling,
  // size change and DPI. Delegates handling of these to member overloads that
  // inheriting classes can handle.
  virtual LRESULT MessageHandler(HWND window,
                                 UINT const message,
                                 WPARAM const wparam,
                                 LPARAM const lparam) noexcept;

  // Called when CreateAndShow is called, allowing subclass window-related
  // setup. Subclasses should return false if setup fails.
  virtual bool OnCreate();

  // Called when Destroy is called.
  virtual void OnDestroy();

  // Messages qui changent la zone de travail : resolution (WM_DISPLAYCHANGE),
  // barre des taches deplacee / redimensionnee / masquee automatiquement
  // (WM_SETTINGCHANGE + SPI_SETWORKAREA). Une fenetre agrandie se recale. Le
  // message n'est JAMAIS consomme : Flutter et le systeme le voient ensuite.
  void OnWorkAreaMessage(UINT const message, WPARAM const wparam);

  // WM_GETMINMAXINFO : taille minimale de la fenetre, et zone de travail comme
  // limite d'un agrandissement fait par le systeme (filet de securite : le
  // poste agrandit lui-meme). |lparam| est le MINMAXINFO du message.
  void FillMinMaxInfo(LPARAM const lparam) const;

 private:
  friend class WindowClassRegistrar;

  // OS callback called by message pump. Handles the WM_NCCREATE message which
  // is passed when the non-client area is being created and enables automatic
  // non-client DPI scaling so that the non-client area automatically
  // responds to changes in DPI. All other messages are handled by
  // MessageHandler.
  static LRESULT CALLBACK WndProc(HWND const window,
                                  UINT const message,
                                  WPARAM const wparam,
                                  LPARAM const lparam) noexcept;

  // Retrieves a class instance pointer for |window|
  static Win32Window* GetThisFromHandle(HWND const window) noexcept;

  // Update the window frame's theme to match the system theme.
  static void UpdateTheme(HWND const window);

  bool quit_on_close_ = false;

  // window handle for top level window.
  HWND window_handle_ = nullptr;

  // window handle for hosted content.
  HWND child_content_ = nullptr;

  // Cale la fenetre sur la zone de travail courante (sans toucher a la position
  // de restauration). Ne fait rien si elle y est deja : pas de boucle de WM_SIZE.
  void FitToWorkArea();

  // Fenetre agrandie dans la zone de travail, et position de restauration.
  bool maximized_ = false;
  RECT restore_rect_ = {0, 0, 0, 0};
};

#endif  // RUNNER_WIN32_WINDOW_H_
