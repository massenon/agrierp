<!DOCTYPE html>
<html lang="fr">
<head><meta charset="utf-8"></head>
<body style="font-family: sans-serif; font-size: 14px; color: #191c1d;">
    <h2 style="color:#052e16;">AgriERP — {{ $payload['type'] === 'bug' ? 'Signalement de bug' : 'Nouveau message' }}</h2>
    <p><strong>De :</strong> {{ $senderName }} ({{ $senderEmail }})</p>
    @if(!empty($payload['device']))
        <p><strong>Appareil :</strong> {{ $payload['device'] }} (poste AgriERP Desktop)</p>
    @endif

    @if($payload['type'] === 'bug')
        <p><strong>Module concerné :</strong> {{ $payload['module'] }}</p>
        <p><strong>Description du problème :</strong><br>{{ $payload['description'] }}</p>
        @if(!empty($payload['steps']))
            <p><strong>Étapes pour reproduire :</strong><br>{{ $payload['steps'] }}</p>
        @endif
        @if($attachmentPath)
            <p><em>Une capture d'écran est jointe à cet e-mail.</em></p>
        @endif
    @else
        <p><strong>Objet :</strong> {{ $payload['subject'] }}</p>
        <p><strong>Message :</strong><br>{{ $payload['message'] }}</p>
    @endif

    <hr style="border:none;border-top:1px solid #bec9c2;margin:16px 0;">
    <p style="color:#6f7973;font-size:11px;">Envoyé automatiquement depuis AgriERP — Ferme École Olouwachegoun.</p>
</body>
</html>
