# Checkmarx One - Authentication API

Source: https://checkmarx.stoplight.io/docs/checkmarx-one-api-reference-guide/fm1ma9xg73dx9-authentication-api

## Description

Generates a JWT access token for authentication with all Checkmarx One APIs.
Token is valid for **30 minutes**.

## Methods

1. **API Key** - Submit API Key → receive access token. Can use refresh token (8h validity) afterwards.
2. **OAuth2 Client** - Submit Client ID + Secret → receive access token. Token inherits OAuth2 Client roles.

## Method: POST

## Regional URLs

| Region | URL |
|--------|-----|
| US | `https://iam.checkmarx.net/auth/realms/{tenant}/protocol/openid-connect/token` |
| US2 | `https://us.iam.checkmarx.net/auth/realms/{tenant}/protocol/openid-connect/token` |
| EU | `https://eu.iam.checkmarx.net/auth/realms/{tenant}/protocol/openid-connect/token` |
| EU2 | `https://eu-2.iam.checkmarx.net/auth/realms/{tenant}/protocol/openid-connect/token` |
| DEU | `https://deu.iam.checkmarx.net/auth/realms/{tenant}/protocol/openid-connect/token` |
| ANZ | `https://anz.iam.checkmarx.net/auth/realms/{tenant}/protocol/openid-connect/token` |
| India | `https://ind.iam.checkmarx.net/auth/realms/{tenant}/protocol/openid-connect/token` |
| Singapore | `https://sng.iam.checkmarx.net/auth/realms/{tenant}/protocol/openid-connect/token` |
| UAE | `https://mea.iam.checkmarx.net/auth/realms/{tenant}/protocol/openid-connect/token` |

## Curl Sample - OAuth2 Client

```bash
curl --request POST 'https://eu.iam.checkmarx.net/auth/realms/{{TENANT_NAME}}/protocol/openid-connect/token' \
  --header 'Content-Type: application/x-www-form-urlencoded' \
  --header 'Accept: application/json' \
  --data-urlencode 'client_id={{your-iam-oauth-client}}' \
  --data-urlencode 'grant_type=client_credentials' \
  --data-urlencode 'client_secret={{secret_key}}'
```

## Curl Sample - Refresh Token

```bash
curl --request POST 'https://eu.iam.checkmarx.net/auth/realms/{{TENANT_NAME}}/protocol/openid-connect/token' \
  --data "grant_type=refresh_token" \
  --data "client_id=ast-app" \
  --data "refresh_token={{Your_API_KEY_OR_REFRESH_TOKEN}}"
```

## Parameters

| Parameter | Required | Type | Values | Description |
|-----------|----------|------|--------|-------------|
| grant_type | Yes | formdata | `refresh_token` or `client_credentials` | Auth credential type |
| client_id | Yes | formdata | `ast-app` (for refresh_token) or OAuth2 Client ID | - |
| refresh_token | For refresh_token grant | formdata | - | API Key or refresh token |
| client_secret | For client_credentials grant | formdata | - | OAuth2 Client Secret |

## Headers

- `Accept: application/json`
- `Content-Type: application/x-www-form-urlencoded`

## Success Response (200)

```json
{
    "access_token": "eyJhbGciOiJSUzI1NiIsInR...phQlk0nAGjOtvG8UT-8iaA",
    "expires_in": 1800,
    "refresh_expires_in": 0,
    "refresh_token": "eyJhbGciOiJIUzI1Ni...Pf43RbBz4M",
    "token_type": "bearer",
    "not-before-policy": 0,
    "session_state": "f4308084-84b5-41af-a326-7c38d9fc19fa",
    "scope": "iam-api profile email ast-api groups offline_access roles"
}
```

## Error Responses

| Status | Message |
|--------|---------|
| 400 | Grant type must be one of the following values: client_credentials / Token is a required field |
| 401 | Not Authorized: Provided token is not valid |
| 405 | Method Not Allowed |
| 500 | Internal Server Error |
