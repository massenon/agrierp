<div style="margin-bottom: 20px;">
    <p><strong>Destinataire :</strong> {{ $customer?->name ?? '—' }}</p>
    @if($customer?->city)
        <p>{{ $customer->city }}</p>
    @endif
    <p><strong>Date :</strong> {{ now()->format('d/m/Y') }}</p>
</div>
<div style="white-space: pre-line; line-height: 1.6;">{{ $message }}</div>
