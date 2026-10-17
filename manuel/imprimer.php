<?php
/**
 * Imprime couverture.html et corps.html en PDF via Chrome (CDP Page.printToPDF).
 * Appelé par build.py — chromedriver doit écouter sur le port 9515.
 */
require 'C:/laragon/www/agrierp/vendor/autoload.php';

use Facebook\WebDriver\Chrome\ChromeDevToolsDriver;
use Facebook\WebDriver\Chrome\ChromeOptions;
use Facebook\WebDriver\Remote\DesiredCapabilities;
use Facebook\WebDriver\Remote\RemoteWebDriver;

$DIR = 'C:/Projects/agrierp_laravel/manuel';

$o = (new ChromeOptions)->addArguments([
    '--headless=new', '--disable-gpu', '--no-sandbox',
    '--window-size=1240,1754', '--allow-file-access-from-files',
]);
$c = DesiredCapabilities::chrome();
$c->setCapability(ChromeOptions::CAPABILITY_W3C, $o);
$d = RemoteWebDriver::create('http://localhost:9515', $c, 180000, 180000);

$entete = '<div style="width:100%;font-family:Arial,sans-serif;font-size:7.5pt;color:#8d968f;'
    . 'padding:0 14mm;display:flex;justify-content:space-between;border-bottom:0.5pt solid #dfe5e1;padding-bottom:3pt;">'
    . '<span style="font-weight:bold;color:#052e16;">AgriERP — Manuel d\'utilisation</span>'
    . '<span>Ferme École Olouwachegoun</span></div>';

$pied = '<div style="width:100%;font-family:Arial,sans-serif;font-size:7.5pt;color:#8d968f;'
    . 'padding:0 14mm;display:flex;justify-content:space-between;border-top:0.5pt solid #dfe5e1;padding-top:3pt;">'
    . '<span>PAEB · Cabinet FAGUEZ SARL · Édité par Dr MASSENON Rhodes — août 2026</span>'
    . '<span>Page <span class="pageNumber"></span> / <span class="totalPages"></span></span></div>';

$base = [
    'landscape' => false,
    'printBackground' => true,
    'paperWidth' => 8.27,
    'paperHeight' => 11.69,
    'preferCSSPageSize' => false,
];

$travaux = [
    ['couverture.html', 'out_couverture.pdf', array_merge($base, [
        'marginTop' => 0, 'marginBottom' => 0, 'marginLeft' => 0, 'marginRight' => 0,
        'displayHeaderFooter' => false,
    ])],
    ['corps.html', 'out_corps.pdf', array_merge($base, [
        'marginTop' => 0.66, 'marginBottom' => 0.62, 'marginLeft' => 0.55, 'marginRight' => 0.55,
        'displayHeaderFooter' => true,
        'headerTemplate' => $entete,
        'footerTemplate' => $pied,
        'generateDocumentOutline' => true,
        'generateTaggedPDF' => true,
    ])],
];

try {
    $cdp = new ChromeDevToolsDriver($d);
    foreach ($travaux as [$src, $dst, $params]) {
        $d->get('file:///' . $DIR . '/' . $src);
        sleep(6);
        $etat = $d->executeScript(
            'const i=[...document.images]; return i.filter(x=>x.complete&&x.naturalWidth>0).length+"/"+i.length;'
        );
        $r = $cdp->execute('Page.printToPDF', $params);
        if (! isset($r['data'])) {
            unset($params['generateDocumentOutline'], $params['generateTaggedPDF']);
            $r = $cdp->execute('Page.printToPDF', $params);
        }
        file_put_contents($DIR . '/' . $dst, base64_decode($r['data']));
        echo '  ' . str_pad($dst, 22) . " images $etat\n";
    }
} finally {
    $d->quit();
}
