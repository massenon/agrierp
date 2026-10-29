<?php

namespace Tests\Feature;

use Tests\TestCase;

/**
 * Décision du client : l'assistant de démarrage n'existe plus, ni au web ni au poste.
 */
class AssistantDemarrageRetireTest extends TestCase
{
    public function test_le_tableau_de_bord_ne_monte_plus_l_assistant(): void
    {
        $vue = file_get_contents(resource_path('views/livewire/dashboard/index.blade.php'));

        $this->assertStringNotContainsString('assistant-demarrage', $vue);
        $this->assertFileDoesNotExist(app_path('Livewire/Parametres/AssistantDemarrage.php'));
        $this->assertFileDoesNotExist(resource_path('views/livewire/parametres/assistant-demarrage.blade.php'));
    }
}
