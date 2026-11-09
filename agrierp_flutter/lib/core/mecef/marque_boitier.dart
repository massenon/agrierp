/// MECEF-2 — la MARQUE LOCALE d'une transmission au boîtier commencée dont on ne connaît pas l'issue.
///
/// Posée dans `sales.mecef_message` (statut `en_attente`) AVANT d'appeler le boîtier : si l'application s'arrête, ou si la réponse
/// du boîtier ne revient pas, la vente porte cette marque. Une vente marquée n'est JAMAIS retransmise automatiquement (le boîtier a
/// peut-être déjà certifié la facture : deux transmissions donneraient deux factures pour une vente) ; l'écran demande de vérifier
/// sur l'appareil, puis de relancer à la main. L'absorbeur du tirage ne l'écrase jamais (voir `SyncEngine._absorberVentes`).
const marqueTransmissionBoitier =
    "Transmission au boîtier commencée, réponse non reçue : vérifiez sur l'appareil (dernière facture) avant de relancer.";

/// Message d'une facture que le boîtier n'a pas pu recevoir : elle attend son retour.
const messageBoitierInjoignable = 'Boîtier injoignable : la facture sera transmise dès son retour.';
