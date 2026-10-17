<?php

namespace App\Livewire\Auth;

use Illuminate\Auth\Events\PasswordReset;
use Illuminate\Support\Facades\Hash;
use Illuminate\Validation\Rules\Password as PasswordRule;
use Illuminate\Support\Facades\Password;
use Illuminate\Support\Str;
use Livewire\Attributes\Layout;
use Livewire\Component;

/**
 * Contrepartie nécessaire de Login::sendResetLink() — voir docblock de
 * Login.php, écart documenté n°5. Absente de l'inventaire des 94 pages du
 * prototype (Document 00 §4) ; ajoutée par nécessité fonctionnelle (un lien
 * de réinitialisation envoyé par e-mail doit mener quelque part), stylée en
 * cohérence avec la charte AgriERP. À confirmer explicitement avec le
 * promoteur au prochain point de synchronisation.
 */
#[Layout('layouts.guest')]
class ResetPassword extends Component
{
    public string $token = '';

    public string $email = '';

    public string $password = '';

    public string $password_confirmation = '';

    public function mount(string $token): void
    {
        $this->token = $token;
        $this->email = request()->query('email', '');
    }

    public function submit(): void
    {
        $this->validate([
            'email' => ['required', 'email'],
            // ⚠️ TICKET 14.65 — la politique vit dans `AppServiceProvider` :
            // `min:8` seul laissait passer « 12345678 ».
            'password' => ['required', 'confirmed', PasswordRule::defaults()],
        ], [
            'password.min' => 'Le mot de passe doit contenir au moins 8 caractères.',
            'password.confirmed' => 'La confirmation ne correspond pas au mot de passe saisi.',
        ]);

        $status = Password::reset(
            [
                'email' => $this->email,
                'password' => $this->password,
                'password_confirmation' => $this->password_confirmation,
                'token' => $this->token,
            ],
            function ($user) {
                $user->forceFill([
                    'password' => Hash::make($this->password),
                    'remember_token' => Str::random(60),
                ])->save();

                event(new PasswordReset($user));
            }
        );

        if ($status !== Password::PASSWORD_RESET) {
            $this->addError('email', 'Ce lien de réinitialisation est invalide ou a expiré. Merci de refaire une demande depuis l\'écran de connexion.');

            return;
        }

        session()->flash('toast', [
            'message' => 'Mot de passe réinitialisé avec succès. Vous pouvez vous connecter.',
            'type' => 'success',
        ]);

        $this->redirect('/login', navigate: false);
    }

    public function render()
    {
        return view('livewire.auth.reset-password');
    }
}
