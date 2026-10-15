// ---------------------------------------------------------------------------
// FS Support : identifiants du compte et serveur de rendez-vous sans échange de clé (15/10/2026).
//
// Bug : dès qu'un compte FS Connect est connecté, le jeton d'accès du compte (`access_token`)
// part dans chaque demande de prise en main (PunchHoleRequest / RequestRelay). Le client amont
// exige alors que le serveur de rendez-vous chiffre la connexion TCP par son échange de clé
// (`secure_tcp`). Or hbbs libre (rustdesk-server, toutes versions jusqu'à 1.1.17) n'envoie jamais
// de KeyExchange : seul le serveur Pro le fait. Le client attendait READ_TIMEOUT (18 s) puis
// abandonnait : « Failed to secure tcp: deadline has elapsed », vers tous les appareils.
//
// Correctif : l'échange est tenté pendant un délai court. S'il aboutit, rien ne change (jeton et
// code d'inversion partent chiffrés). Si le serveur ne le fait pas, la connexion repart sur un
// socket neuf, SANS le jeton ni le code d'inversion : exactement ce qu'envoie un client non
// connecté, qui fonctionne. hbbs libre ignore ces deux champs (il ne les lit pas) et recopie
// RequestRelay tel quel à l'appareil distant, en clair : ne pas les envoyer est donc aussi plus
// sûr. Un échange commencé puis invalide (signature fausse) reste une erreur bloquante, comme
// avant : le correctif ne dégrade rien quand le serveur fait l'échange.
//
// Le serveur reconnu sans échange est mémorisé pour la durée du processus : les connexions
// suivantes (et les trois tentatives de relais) n'attendent plus.
// ---------------------------------------------------------------------------

use std::{collections::HashSet, sync::Mutex, time::Duration};

use hbb_common::{
    config::CONNECT_TIMEOUT, log, socket_client::connect_tcp, tokio::time::timeout, ResultType,
    Stream,
};

/// Attente maximale de l'échange de clé du serveur. Un serveur qui le fait l'envoie dès
/// l'acceptation de la connexion : quelques secondes couvrent largement une liaison lente.
pub(crate) const DELAI_ECHANGE: Duration = Duration::from_secs(4);

lazy_static::lazy_static! {
    static ref SERVEURS_SANS_ECHANGE: Mutex<HashSet<String>> = Mutex::new(HashSet::new());
}

fn serveur_connu_sans_echange(serveur: &str) -> bool {
    SERVEURS_SANS_ECHANGE
        .lock()
        .map(|s| s.contains(serveur))
        .unwrap_or(false)
}

fn noter_serveur_sans_echange(serveur: &str) {
    if let Ok(mut s) = SERVEURS_SANS_ECHANGE.lock() {
        s.insert(serveur.to_owned());
    }
}

/// Faut-il protéger quelque chose sur ce socket ? Même règle que le client amont : une clé de
/// serveur et un jeton de compte ou un code d'inversion à transmettre.
pub(crate) fn identifiants_a_proteger(key: &str, token: &str, switch_code: &str) -> bool {
    !key.is_empty() && (!token.is_empty() || !switch_code.is_empty())
}

/// Sécurise `socket` avant d'y envoyer le jeton du compte ou le code d'inversion.
///
/// `Ok(true)` : le canal est chiffré (ou WebSocket sécurisé), les identifiants peuvent partir.
/// `Ok(false)` : le serveur ne fait pas l'échange ; `socket` a été remplacé par une connexion
/// neuve en clair et l'appelant DOIT vider le jeton et le code d'inversion avant d'envoyer.
/// `Err` : échange commencé puis invalide, ou reconnexion impossible.
pub(crate) async fn securiser_ou_retirer_identifiants(
    socket: &mut Stream,
    rendezvous_server: &str,
    key: &str,
    delai: Duration,
) -> ResultType<bool> {
    if !serveur_connu_sans_echange(rendezvous_server) {
        match timeout(delai, crate::common::secure_tcp_attempt(socket, key)).await {
            Ok(Ok(true)) => return Ok(true),
            Ok(Err(err)) => return Err(err),
            Ok(Ok(false)) => {
                log::warn!(
                    "FS Support : {} ne fait pas l'échange de clé, connexion sans les identifiants du compte",
                    rendezvous_server
                );
            }
            Err(_) => {
                log::warn!(
                    "FS Support : pas d'échange de clé de {} en {:?}, connexion sans les identifiants du compte",
                    rendezvous_server,
                    delai
                );
            }
        }
        noter_serveur_sans_echange(rendezvous_server);
    }
    // Socket neuf : l'essai a pu consommer un message, ou être interrompu au milieu d'une lecture.
    *socket = connect_tcp(rendezvous_server, CONNECT_TIMEOUT).await?;
    Ok(false)
}

#[cfg(test)]
mod tests {
    use super::*;
    use hbb_common::{
        protobuf::Message as _,
        rendezvous_proto::*,
        sodiumoxide::crypto::{box_, sign},
        tcp::FramedStream,
        tokio,
    };

    /// Faux serveur de rendez-vous sur la boucle locale : accepte `n` connexions, chacune servie
    /// par `serve`. Renvoie l'adresse et le nombre de connexions reçues.
    async fn faux_serveur<F, Fut>(
        n: usize,
        serve: F,
    ) -> (String, std::sync::Arc<std::sync::atomic::AtomicUsize>)
    where
        F: Fn(FramedStream) -> Fut + Send + Sync + 'static,
        Fut: std::future::Future<Output = ()> + Send + 'static,
    {
        let listener = hbb_common::tcp::new_listener("127.0.0.1:0", false)
            .await
            .unwrap();
        let host = listener.local_addr().unwrap().to_string();
        let compte = std::sync::Arc::new(std::sync::atomic::AtomicUsize::new(0));
        let compte2 = compte.clone();
        tokio::spawn(async move {
            for _ in 0..n {
                if let Ok((stream, addr)) = listener.accept().await {
                    compte2.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
                    tokio::spawn(serve(FramedStream::from(stream, addr)));
                }
            }
        });
        (host, compte)
    }

    fn cle_serveur() -> (String, sign::SecretKey) {
        let (pk, sk) = sign::gen_keypair();
        (crate::common::encode64(pk.0), sk)
    }

    async fn connecter(host: &str) -> Stream {
        connect_tcp(host.to_owned(), 3000).await.unwrap()
    }

    #[test]
    fn fs_rendezvous_regle_des_identifiants() {
        assert!(identifiants_a_proteger("cle", "jeton", ""));
        assert!(identifiants_a_proteger("cle", "", "code"));
        assert!(!identifiants_a_proteger("cle", "", ""));
        assert!(!identifiants_a_proteger("", "jeton", "code"));
    }

    /// hbbs libre : n'envoie rien et attend la demande du client. La connexion continue, sur un
    /// socket neuf, sans identifiants, et le serveur est mémorisé (pas de nouvelle attente).
    #[tokio::test]
    async fn fs_rendezvous_serveur_muet_la_connexion_continue() {
        let (key, _) = cle_serveur();
        let (host, compte) = faux_serveur(10, |mut s| async move {
            // Comme hbbs : lit ce que le client envoie, ne parle jamais le premier.
            while let Some(Ok(_)) = s.next_timeout(10_000).await {}
        })
        .await;
        let mut socket = connecter(&host).await;
        let debut = std::time::Instant::now();
        let secure = securiser_ou_retirer_identifiants(
            &mut socket,
            &host,
            &key,
            Duration::from_millis(500),
        )
        .await
        .unwrap();
        assert!(!secure);
        assert!(!socket.is_secured());
        assert!(debut.elapsed() < Duration::from_secs(5), "attente non bornée");
        // Le socket rendu est utilisable : une demande part sans erreur.
        let mut msg = RendezvousMessage::new();
        msg.set_punch_hole_request(PunchHoleRequest {
            id: "123456789".to_owned(),
            ..Default::default()
        });
        socket.send(&msg).await.unwrap();
        tokio::time::sleep(Duration::from_millis(300)).await;
        // Connexion d'origine + socket neuf.
        assert_eq!(compte.load(std::sync::atomic::Ordering::SeqCst), 2);

        // Deuxième connexion vers le même serveur : aucune attente.
        let mut socket = connecter(&host).await;
        let debut = std::time::Instant::now();
        let secure = securiser_ou_retirer_identifiants(
            &mut socket,
            &host,
            &key,
            Duration::from_secs(30),
        )
        .await
        .unwrap();
        assert!(!secure);
        assert!(debut.elapsed() < Duration::from_secs(5), "serveur non mémorisé");
    }

    /// Ancien serveur qui répond autre chose qu'un KeyExchange : même repli, sans attendre le délai.
    #[tokio::test]
    async fn fs_rendezvous_serveur_sans_echange_qui_repond() {
        let (key, _) = cle_serveur();
        let (host, _) = faux_serveur(2, |mut s| async move {
            let mut msg = RendezvousMessage::new();
            msg.set_register_peer_response(RegisterPeerResponse::new());
            s.send(&msg).await.ok();
            while let Some(Ok(_)) = s.next_timeout(10_000).await {}
        })
        .await;
        let mut socket = connecter(&host).await;
        let debut = std::time::Instant::now();
        let secure =
            securiser_ou_retirer_identifiants(&mut socket, &host, &key, Duration::from_secs(30))
                .await
                .unwrap();
        assert!(!secure);
        assert!(!socket.is_secured());
        assert!(debut.elapsed() < Duration::from_secs(5));
    }

    /// Serveur qui fait l'échange (Pro) : le canal est chiffré, les identifiants peuvent partir.
    #[tokio::test]
    async fn fs_rendezvous_serveur_avec_echange_chiffre() {
        let (key, sk) = cle_serveur();
        let sk = std::sync::Arc::new(sk);
        let (host, compte) = faux_serveur(1, move |mut s| {
            let sk = sk.clone();
            async move {
                let (eph_pk, eph_sk) = box_::gen_keypair();
                let mut msg = RendezvousMessage::new();
                msg.set_key_exchange(KeyExchange {
                    keys: vec![sign::sign(&eph_pk.0, &sk).into()],
                    ..Default::default()
                });
                s.send(&msg).await.unwrap();
                let reply = s.next_timeout(3000).await.unwrap().unwrap();
                let reply = RendezvousMessage::parse_from_bytes(&reply).unwrap();
                let Some(rendezvous_message::Union::KeyExchange(ex)) = reply.union else {
                    panic!("échange de clé du client attendu");
                };
                hbb_common::tcp::Encrypt::decode(&ex.keys[1], &ex.keys[0], &eph_sk).unwrap();
            }
        })
        .await;
        let mut socket = connecter(&host).await;
        let secure =
            securiser_ou_retirer_identifiants(&mut socket, &host, &key, Duration::from_secs(4))
                .await
                .unwrap();
        assert!(secure);
        assert!(socket.is_secured());
        // Pas de reconnexion : le socket chiffré est gardé.
        assert_eq!(compte.load(std::sync::atomic::Ordering::SeqCst), 1);
    }

    /// Échange commencé mais signé par une autre clé : erreur, jamais de repli en clair.
    #[tokio::test]
    async fn fs_rendezvous_echange_invalide_reste_une_erreur() {
        let (key, _) = cle_serveur();
        let (_, autre_sk) = cle_serveur();
        let autre_sk = std::sync::Arc::new(autre_sk);
        let (host, _) = faux_serveur(2, move |mut s| {
            let autre_sk = autre_sk.clone();
            async move {
                let (eph_pk, _) = box_::gen_keypair();
                let mut msg = RendezvousMessage::new();
                msg.set_key_exchange(KeyExchange {
                    keys: vec![sign::sign(&eph_pk.0, &autre_sk).into()],
                    ..Default::default()
                });
                s.send(&msg).await.ok();
                while let Some(Ok(_)) = s.next_timeout(5_000).await {}
            }
        })
        .await;
        let mut socket = connecter(&host).await;
        assert!(
            securiser_ou_retirer_identifiants(&mut socket, &host, &key, Duration::from_secs(4))
                .await
                .is_err()
        );
        // Et le serveur n'est pas mémorisé « sans échange ».
        assert!(!serveur_connu_sans_echange(&host));
    }
}
