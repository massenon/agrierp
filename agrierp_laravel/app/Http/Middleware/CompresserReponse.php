<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * PWA-PERF — compresse les réponses HTML/JS/CSS/JSON par gzip quand le serveur web
 * (nginx/Apache) ne le fait pas déjà (détecté par l'absence de Content-Encoding).
 *
 * À n'activer que si la compression n'est pas gérée en amont (Laragon local, dev, recette).
 * En production, préférer la compression nginx (gzip on; gzip_types …) : plus efficace.
 */
class CompresserReponse
{
    public function handle(Request $request, Closure $next): Response
    {
        /** @var Response $reponse */
        $reponse = $next($request);

        // Ne pas recompresser ce qui l'est déjà (nginx, CDN).
        if ($reponse->headers->has('Content-Encoding')) {
            return $reponse;
        }

        // Ne compresser que les types textuels compressibles.
        $type = $reponse->headers->get('Content-Type', '');
        $compressible = str_contains($type, 'text/html')
            || str_contains($type, 'text/css')
            || str_contains($type, 'application/javascript')
            || str_contains($type, 'text/javascript')
            || str_contains($type, 'application/json')
            || str_contains($type, 'image/svg+xml');

        if (! $compressible) {
            return $reponse;
        }

        $accepte = $request->header('Accept-Encoding', '');

        if (function_exists('brotli_compress') && str_contains($accepte, 'br')) {
            $compresse = brotli_compress($reponse->getContent(), 4);
            if ($compresse !== false) {
                $reponse->setContent($compresse);
                $reponse->headers->set('Content-Encoding', 'br');
                $reponse->headers->set('Content-Length', (string) strlen($compresse));
                $reponse->headers->addCacheControlDirective('no-transform');
            }
        } elseif (str_contains($accepte, 'gzip')) {
            $compresse = gzencode($reponse->getContent(), 6);
            if ($compresse !== false) {
                $reponse->setContent($compresse);
                $reponse->headers->set('Content-Encoding', 'gzip');
                $reponse->headers->set('Content-Length', (string) strlen($compresse));
                $reponse->headers->addCacheControlDirective('no-transform');
            }
        }

        return $reponse;
    }
}
