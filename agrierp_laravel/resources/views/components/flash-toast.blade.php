@if(session('toast'))
    <div
        x-data
        x-init="window.dispatchEvent(new CustomEvent('toast', { detail: @js(session('toast')) }))">
    </div>
@endif
