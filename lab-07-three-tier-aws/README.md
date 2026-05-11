# Lab 07 — Three-Tier AWS Architecture (HA)

Déploiement complet d'une architecture web 3-tier hautement disponible sur AWS,
avec **coûts optimisés** pour du test/dev.

## Architecture

```
     🌐 Internet
         │
    ┌────┴────┐
    │ 🛡️ WAF  │  Rate Limit (500/5min) + SQLi + Common Rules
    └────┬────┘
         │
    ┌────┴────┐
    │ ⚖️  ALB │  Internet-facing, cross-AZ
    └────┬────┘
         │
    ┌────┴───────────┐
    │                │
┌───┴───┐      ┌────┴───┐
│ App 1 │      │ App 2  │  Python Flask :5000
│ AZ 1a │      │ AZ 1b  │  t3.micro ×2
└───┬───┘      └────┬───┘
    │               │
    └───────┬───────┘
            │
    ┌───────┴───────┐
    │ 🗄️ RDS MySQL  │  Multi-AZ (1a + 1b standby)
    └───────────────┘
            │
    ┌───────┴───────┐
    │  📦 S3 Bucket │  via VPC Gateway Endpoint
    └───────────────┘
```

## Composants

| Composant | Type | Détail |
|---|---|---|
| VPC | `10.0.0.0/16` | 2 public + 2 private subnets |
| Web Tier | t3.micro EC2 | Apache Reverse Proxy → ALB |
| App Tier | t3.micro EC2 ×2 | Python Flask, S3 upload/download |
| DB Tier | db.t3.micro RDS | MySQL 8.0, Multi-AZ |
| ALB | Application LB | HTTP:80 → App Target Group |
| WAF | Web ACL | Rate Limit + SQLi + Common Rules |
| S3 | Bucket | Chiffré, versionné, privé |
| VPC Endpoint | S3 Gateway | Route privée → S3 |

## Security Groups (3-Tier Enforced)

```
Web SG → :80 world, :22 world
   ↓
ALB SG → :80 world
   ↓
App SG → :5000 from Web SG + ALB SG, :22 from Web SG
   ↓
DB SG  → :3306 from App SG
```

## Endpoints API

| Méthode | Endpoint | Description |
|---|---|---|
| `GET` | `/api/status` | Santé app + hostname |
| `GET` | `/api/db` | Test connexion RDS |
| `GET` | `/api/files` | Liste fichiers S3 |
| `POST` | `/api/upload` | Upload fichier → S3 |
| `GET` | `/api/download/<key>` | URL présignée S3 |

## Coût (24/7)

| Ressource | /jour |
|---|---|
| 2× t3.micro | ~$0.50 |
| RDS Multi-AZ | ~$0.82 |
| ALB | ~$0.54 |
| WAF | ~$0.60 |
| S3 + VPC Endpoint | ~négligeable |
| **TOTAL** | **~$2.46/j (~$75/mois)** |

## Déploiement

```bash
# 1. Déployer l'infrastructure
bash deploy.sh

# 2. Accéder au dashboard
open http://<WEB_PUBLIC_IP>

# 3. Détruire TOUT
bash teardown.sh
```

## Prérequis

- AWS CLI configuré avec un profil (`iamadmin` par défaut)
- Région `us-east-1`
- Droits : EC2, RDS, ELB, WAF, S3, IAM, VPC

## Fichiers

| Fichier | Description |
|---|---|
| `deploy.sh` | Script de déploiement complet |
| `teardown.sh` | Détruit toutes les ressources |
| `app.py` | Application Flask (App Tier) |
