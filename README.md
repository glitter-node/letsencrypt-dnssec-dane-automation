# Let's Encrypt Multi-Domain Certificate Automation

**DNSSEC and DANE/TLSA Integrated Certificate Renewal Architecture**

## Overview

여러 도메인의 Let's Encrypt 인증서 갱신을 DNS-01 인증, DNSSEC, 서비스 인증서 배포, 원격 서버 동기화 및 DANE/TLSA 동기화와 연계하는 자동화 설계 사례입니다.

일반적인 인증서 자동 갱신을 넘어, 인증서 변경에 따라 DNS 보안 상태와 실제 서비스의 TLS 인증 상태가 일관성을 유지하도록 관리하는 것을 목표로 합니다.

이 프로젝트는 Certbot을 기반으로 다음 작업을 하나의 자동화 흐름으로 연결하는 아키텍처와 참고 소스를 소개합니다.

- 다중 도메인 인증서 관리
- DNS-01 기반 ACME 인증
- DNSSEC 서명 영역과 일반 DNS 영역의 구분
- 인증서 변경 감지 및 선택적 배포
- 로컬 및 원격 서버 인증서 동기화
- DANE/TLSA 레코드 동기화
- 작업 잠금, 오류 처리 및 실행 결과 관리

실제 운영 환경을 복제한 배포 패키지가 아니라 설계 방식과 구현 예제를 공유하기 위한 프로젝트입니다.

## Design Goals

### 1. Multi-Domain Certificate Management

여러 인증서를 하나의 관리자로 통합하여 순차적으로 처리합니다.

각 인증서는 독립적인 갱신 설정을 유지하며, 개별 갱신 결과와 전체 작업 결과를 구분하여 관리합니다.

### 2. DNS-01 and DNSSEC Integration

DNS-01 인증 과정에서 ACME 검증용 TXT 레코드를 등록하고 정리합니다.

DNSSEC 서명이 필요한 영역에서는 DNS 레코드 변경에 따른 서명 및 배포 절차를 연계합니다.

DNSSEC 서명 여부는 인증서 이름이 아니라 실제 DNS 영역을 기준으로 판단합니다.

DNS 공급자가 자동 서명을 지원하는 환경에서는 별도의 서명 작업을 수행하지 않을 수 있습니다.

### 3. Certificate Change Detection

인증서 갱신 전후의 SHA-256 해시를 비교하여 실제 인증서 변경 여부를 판단합니다.

인증서가 변경되지 않았다면 불필요한 서비스 재시작이나 배포를 생략합니다.

인증서가 변경된 경우에만 후속 배포 작업을 진행합니다.

### 4. DANE/TLSA Synchronization

DANE를 사용하는 서비스에서는 DNS의 TLSA 레코드와 실제 서비스 인증서의 일관성이 중요합니다.

인증서 또는 공개키가 변경되면 TLSA 레코드의 사용 방식에 따라 갱신 여부를 판단합니다.

인증서 배포와 TLSA 레코드 변경은 서로 독립적인 작업이 아니라 상호 일관성을 고려해야 하는 작업입니다.

특히 공개키 교체가 발생하는 경우 DNS 전파, TLSA 레코드 변경 및 서비스 인증서 배포 순서를 고려한 안전한 전환이 필요합니다.

### 5. Remote Certificate Synchronization

인증서 갱신 서버와 실제 서비스를 운영하는 서버가 분리된 환경을 고려합니다.

인증서가 변경되면 사전에 정의된 원격 서버에 인증서 파일을 안전하게 전송하고 각 서버의 서비스 환경에 맞게 동기화하는 구조를 설계합니다.

주요 고려 사항은 다음과 같습니다.

- SSH 기반 원격 서버 인증 및 파일 전송
- 서버별 인증서 배포 대상과 경로 관리
- 인증서 및 개인키의 안전한 전송
- 원격 서버의 파일 권한과 소유권 설정
- 전송된 인증서의 무결성 확인
- 원격 서비스의 인증서 적용 및 reload
- 원격 서버별 배포 결과 확인
- 배포 실패 시 오류 기록 및 재시도
- 일부 원격 서버의 실패가 전체 작업에 미치는 영향 관리

원격 서버 동기화는 인증서 갱신과 서비스 배포를 분리하여 관리하며, 인증서가 실제로 변경된 경우에만 실행하도록 설계합니다.

### 6. Reliability & Execution Control

동시 실행 방지, 인증서별 오류 처리, 실패 결과 집계 및 작업 이력 관리를 고려합니다.

일부 인증서 또는 원격 서버의 작업이 실패하더라도 나머지 작업을 처리할 수 있도록 하되, 최종 실행 결과에서는 실패가 명확하게 드러나도록 설계합니다.

## Architecture

전체 자동화 흐름은 다음과 같습니다.

```text
Certificate Renewal Manager
          |
          v
    Certbot / ACME
          |
          v
      DNS-01 Auth
          |
          v
  TXT Record Registration
          |
          v
    DNSSEC Processing
   (When Required)
          |
          v
 DNS Propagation Check
          |
          v
    ACME Validation
          |
          v
   TXT Record Cleanup
          |
          v
    DNSSEC Re-signing
   (When Required)
          |
          v
 Certificate Renewal
          |
          v
 Certificate Change Detection
          |
          +----------------------+
          |                      |
       Unchanged               Changed
          |                      |
          v                      v
        Skip             Certificate Deployment
                                 |
                                 v
                       Remote Certificate Sync
                          (When Configured)
                                 |
                                 v
                       DANE/TLSA Synchronization
                           (When Enabled)
                                 |
                                 v
                         Service Verification
```

위 다이어그램은 전체 시스템의 목표 처리 흐름을 나타냅니다. 실제 구현에서는 DNS 공급자의 기능과 DNSSEC 운영 방식, 서비스 구성 및 원격 서버의 배포 방식에 따라 일부 단계를 통합하거나 생략할 수 있습니다.

## DNS Security Architecture

DNS 보안 기능은 DNSSEC와 DANE/TLSA를 구분하여 관리합니다.

### DNSSEC-Signed Zones

DNSSEC가 적용된 DNS 영역에서는 DNS 레코드 변경 이후 유효한 서명 상태를 유지해야 합니다.

DNS-01 인증에 사용되는 TXT 레코드의 등록과 삭제 역시 DNSSEC 영역의 변경 작업에 포함됩니다.

설계상 고려 사항은 다음과 같습니다.

- TXT 레코드 등록 및 삭제
- DNSSEC 서명 또는 자동 서명 확인
- 권한 DNS 서버로의 변경 사항 배포
- 외부 DNS 조회를 통한 검증
- 서명 오류 발생 시 후속 인증 중단

### Standard DNS Zones

DNSSEC를 사용하지 않는 영역은 일반 DNS 레코드 변경 절차를 사용합니다.

DNSSEC 처리와 분리하여 불필요한 서명 작업을 수행하지 않도록 합니다.

### Independent DANE Policy

DNSSEC와 DANE/TLSA는 서로 다른 보안 기능입니다.

DNSSEC는 DNS 데이터의 무결성과 출처를 검증하는 체계이며, DANE는 DNSSEC로 보호되는 DNS 정보를 활용하여 TLS 인증서 또는 공개키를 검증하는 체계입니다.

따라서 DNSSEC 적용 여부와 DANE 사용 여부는 독립적인 정책으로 관리합니다.

## Certificate Deployment Strategy

인증서 갱신과 서비스 배포는 구분하여 처리합니다.

1. 인증서 갱신 전후의 인증서 해시를 비교합니다.
2. 인증서가 변경되지 않았다면 배포를 생략합니다.
3. 인증서가 변경되었다면 해당 서비스의 인증서 파일을 배포합니다.
4. 서비스가 새로운 인증서를 정상적으로 제공하는지 확인합니다.
5. 원격 서버가 구성되어 있다면 해당 서버에 인증서를 동기화합니다.
6. DANE/TLSA 사용 서비스라면 TLSA 레코드와의 일관성을 확인합니다.

인증서 배포는 서비스별 구성에 따라 로컬 서버와 원격 서버를 구분하여 처리할 수 있습니다.

서비스에 적용하기 전 인증서와 개인키의 일치 여부, 인증서 체인 및 파일 권한을 확인하는 절차를 고려합니다.

DANE/TLSA 전환 시에는 기존 인증서와 신규 인증서가 공존하는 전환 기간을 고려할 수 있습니다.

특히 TLSA 레코드가 인증서 또는 공개키에 직접 연결되는 경우, 신규 레코드의 DNS 전파가 완료되기 전에 기존 인증서를 제거하지 않도록 주의해야 합니다.

## Remote Certificate Synchronization Strategy

원격 서버 인증서 동기화는 인증서 갱신 관리자와 실제 서비스를 운영하는 서버 사이의 배포 작업을 담당합니다.

### Remote Server Configuration

원격 서버별로 다음 정보를 관리하는 구조를 고려합니다.

- 원격 서버 식별자
- SSH 접속 대상 및 인증 방식
- 인증서 배포 대상 경로
- 인증서 및 개인키 파일
- 파일 소유권과 접근 권한
- 적용 대상 서비스
- 서비스별 reload 또는 재시작 명령

실제 서버 주소와 인증 정보는 공개 설정 파일에 포함하지 않고 별도의 환경별 설정으로 관리합니다.

### Secure Transfer

SSH 기반 전송 방식을 사용하여 인증서 파일을 원격 서버로 전달하는 구조를 제안합니다.

개인키가 포함되는 경우 전송 과정뿐 아니라 원격 서버에서의 저장 권한과 접근 통제도 고려해야 합니다.

### Remote Deployment Verification

원격 서버에 파일을 전송한 이후 다음 사항을 확인합니다.

1. 전송된 파일의 무결성
2. 인증서와 개인키의 일치 여부
3. 인증서 체인의 유효성
4. 파일 권한 및 소유권
5. 서비스 설정의 정상 여부
6. 실제 서비스가 새로운 인증서를 제공하는지 여부

### Failure Handling

여러 원격 서버에 배포하는 경우 서버별 작업 결과를 독립적으로 관리합니다.

일부 서버의 배포가 실패하더라도 다른 서버의 결과를 확인할 수 있도록 하며, 실패한 서버에 대해서는 재시도 또는 복구 절차를 수행할 수 있도록 설계합니다.

원격 서버 동기화와 배포는 현재 아키텍처에서 고려하는 기능이며, 실제 SSH 전송 및 원격 서비스 제어는 환경별 구현이 필요합니다.

## Configuration Strategy

설정은 인증서 목록과 DNS 보안 정책, 서비스 배포 정책을 분리하는 방향으로 구성합니다.

### Certificate Configuration

인증서 식별자와 Certbot 관리 설정을 정의합니다.

### DNS Zone Mapping

인증 대상 도메인을 실제 관리 DNS 영역에 연결합니다.

하위 도메인의 DNS-01 인증이 상위 DNS 영역에서 관리되는 경우에도 올바른 영역을 선택할 수 있도록 합니다.

### DNSSEC Policy

DNS 영역별 DNSSEC 적용 여부를 정의합니다.

### DANE Policy

인증서 또는 서비스별 DANE/TLSA 사용 여부를 독립적으로 정의합니다.

### Deployment Policy

인증서별 서비스 배포 대상과 배포 방식을 정의합니다.

로컬 서비스와 원격 서버를 구분하고, 각 대상의 인증서 경로와 서비스 적용 절차를 관리하는 구조를 고려합니다.

이러한 분리 구조를 통해 인증서 관리 정책과 DNS 보안 및 서비스 배포 정책의 종속성을 줄일 수 있습니다.

## Reliability and Execution Control

자동화 작업의 안정성을 위해 다음 사항을 고려합니다.

- 동시 실행 방지를 위한 파일 잠금
- 인증서별 갱신 결과 확인
- 갱신 전후 인증서 변경 감지
- 개별 작업 실패와 전체 작업 결과의 분리
- DNS 변경 실패 시 후속 단계 중단
- 인증서 배포 및 DNS 동기화 결과 확인
- 원격 서버별 전송 및 적용 결과 관리
- 배포 실패 시 재시도 및 복구 처리
- 로그를 통한 작업 이력 관리

일부 인증서 또는 원격 서버의 갱신 및 배포가 실패하더라도 나머지 작업을 진행할 수 있도록 하되, 최종 실행 결과에서는 실패가 명확하게 드러나도록 설계합니다.

## Repository Structure

```text
.
├── README.md
├── .gitignore
├── config.example/
│   └── domains.conf
└── src/
    ├── renew-all.sh
    └── hooks/
        ├── auth.sh
        ├── cleanup.sh
        ├── dns-provider.sh
        ├── dns-propagation.sh
        └── dnssec-sign.sh
```

각 파일의 역할은 다음과 같습니다.

| File | Description |
|---|---|
| `src/renew-all.sh` | 인증서 순차 갱신 및 변경 감지 |
| `config.example/domains.conf` | 인증서와 DNS 보안 정책 설정 예제 |
| `src/hooks/auth.sh` | DNS-01 인증용 TXT 등록 흐름 |
| `src/hooks/cleanup.sh` | TXT 레코드 정리 흐름 |
| `src/hooks/dns-provider.sh` | DNS 공급자 연동 인터페이스 |
| `src/hooks/dns-propagation.sh` | DNS 전파 확인 인터페이스 |
| `src/hooks/dnssec-sign.sh` | DNSSEC 서명 연동 인터페이스 |

원격 서버 동기화, 서비스별 인증서 배포 및 DANE/TLSA 처리는 현재 별도 구현이 필요한 확장 영역입니다.

## Implementation Status

이 저장소는 아키텍처 소개와 참고 구현을 목적으로 합니다.

현재 포함된 코드는 인증서 갱신 관리자와 설정 구조, DNS-01 및 DNSSEC 처리 흐름을 설명하는 인터페이스 예제입니다.

다음 기능은 실제 운영 환경에 맞는 별도 구현이 필요합니다.

- DNS 공급자 API 연동
- DNSSEC 서명 및 배포
- 권한 DNS 서버 기반 TXT 전파 검증
- 인증서 서비스별 배포
- SSH 기반 원격 서버 인증서 전송 및 동기화
- 원격 서비스 reload 및 배포 결과 확인
- DANE/TLSA 레코드 생성 및 동기화
- 전체 작업의 통합 검증 및 복구 처리

따라서 이 저장소의 코드를 완성된 자동화 배포 도구로 간주해서는 안 됩니다.

## Security Considerations

실제 운영 환경의 민감한 정보는 공개 저장소에 포함하지 않습니다.

- 실제 도메인 및 서버 주소
- 인증서 개인키 및 계정 정보
- DNS 공급자 API 인증 정보
- SSH 개인키 및 원격 서버 인증 정보
- 운영 서버의 파일 시스템 경로
- 내부 서비스 및 배포 설정

공개 예제의 도메인과 식별자는 설명을 위한 가상 값입니다.

원격 서버에 개인키를 전송하는 경우 SSH 인증, 최소 권한 원칙, 파일 접근 권한 및 전송 대상 서버의 신뢰성을 고려해야 합니다.

운영 환경에 적용하기 전에는 각 DNS 공급자와 서비스, 원격 서버의 동작 방식에 맞게 수정하고 충분히 검증해야 합니다.

## Purpose

이 프로젝트는 인증서 자동 갱신을 단순한 정기 작업으로 취급하지 않고, DNS 보안, TLS 인증 신뢰, 원격 서버 간 인증서 배포 및 서비스 운영의 연속성을 함께 고려하는 운영 자동화 설계 사례를 공유하는 데 목적이 있습니다.

또한 유사한 자동화 시스템을 직접 구축하려는 개발자에게 설계 방향과 참고 구현을 제공하여, 각자의 운영 환경에 맞는 시스템을 구성할 수 있도록 돕고자 합니다.

**Certificate Renewal, DNSSEC, DANE/TLSA, and Remote Deployment — Managed as One Consistent Security Workflow.**
