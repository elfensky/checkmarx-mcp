# Checkmarx One - Projects API

Source: https://checkmarx.stoplight.io/docs/checkmarx-one-api-reference-guide/ry3bnvw1ikz2h-projects-rest-api

## Retrieve List of Projects

Get a list of projects in your account. Returns general info for projects, including mapping of Project Name to Project ID.

You can get info for all projects, or limit results using pagination and/or by filtering by various scan attributes such as Project ID, Project Name, tags, etc.

**Method:** GET

## Regional URLs

| Region | URL |
|--------|-----|
| US | `https://ast.checkmarx.net/api/projects` |
| US2 | `https://us.ast.checkmarx.net/api/projects` |
| EU | `https://eu.ast.checkmarx.net/api/projects` |
| EU2 | `https://eu-2.ast.checkmarx.net/api/projects` |
| DEU | `https://deu.ast.checkmarx.net/api/projects` |
| ANZ | `https://anz.ast.checkmarx.net/api/projects` |
| India | `https://ind.ast.checkmarx.net/api/projects` |
| Singapore | `https://sng.ast.checkmarx.net/api/projects` |
| UAE | `https://mea.ast.checkmarx.net/api/projects` |

## Headers

| Header | Required | Type | Description |
|--------|----------|------|-------------|
| Authorization | Yes | JWT | JWT access token |
| Accept | Yes | string | Media type with API version, e.g. `*/*; version=1.0` (pattern: `.*version\s*=\s*([\d|.]+)`) |
| CorrelationId | No | string (uuid) | For internal Checkmarx use |

## Query Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| offset | integer (>= 0) | 0 | The number of results to skip before starting to return results |
| limit | integer (<= 100) | 20 | The maximum number of records to return |
| ids | array[string] | - | Filter by project IDs. Only exact matches are returned. (OR operator for multiple IDs) |
| name | string | - | Filter by a string used in project names. Results returned if the string is part of the project name. Mutually exclusive with `names` and `name-regex` |
| names | array[string] | - | Filter by project names. Only exact matches are returned. Mutually exclusive with `name` and `name-regex`. (OR operator for multiple names) |
| name-regex | string | - | Filter by a regex used in project names. Mutually exclusive with `name` and `names` |
| groups | array[string] | - | Filter by Group IDs of the user groups assigned to the project. Only exact matches. (OR operator for multiple groups) |
| tags-keys | array[string] | - | Filter by tag keys (of key:value pairs) associated with your projects. (OR operator for multiple keys) |
| tags-values | array[string] | - | Filter by tag values (of key:value pairs) associated with your projects. (OR operator for multiple values) |
| repo-url | string | - | Filter by repo URL of the projects |

## Curl Sample

```bash
curl --request GET 'https://ast.checkmarx.net/api/projects?offset=0&limit=20' \
  --header 'Authorization: Bearer {{access_token}}' \
  --header 'Accept: */*; version=1.0'
```

### With Filters

```bash
curl --request GET 'https://ast.checkmarx.net/api/projects?name=my-project&limit=10' \
  --header 'Authorization: Bearer {{access_token}}' \
  --header 'Accept: */*; version=1.0'
```

## Success Response (200)

```json
{
    "totalCount": 150,
    "filteredTotalCount": 2,
    "projects": [
        {
            "id": "project-uuid-here",
            "name": "my-project",
            "tenantId": "tenant-uuid-here",
            "createdAt": "2024-01-15T10:30:00Z",
            "updatedAt": "2024-06-20T14:45:00Z",
            "groups": [],
            "tags": {
                "environment": "production",
                "team": "backend"
            },
            "repoUrl": "https://github.com/org/my-project.git",
            "mainBranch": "main",
            "origin": "GitHub",
            "criticality": 3,
            "privatePackage": false
        }
    ]
}
```

### Response Fields

| Field | Type | Description |
|-------|------|-------------|
| totalCount | integer | The total number of records in the account |
| filteredTotalCount | integer | The total number of records matching the applied filter |
| projects | array[object] | The projects returned with the filter applied |
| projects[].id | string | The unique identifier of the project |
| projects[].name | string | The name of the project |
| projects[].tenantId | string | The ID of the tenant account |
| projects[].createdAt | string | UTC timestamp of when the project was created |
| projects[].updatedAt | string | UTC timestamp of when the project was last updated |
| projects[].groups | array[object] | Group IDs of user groups authorized to access this project |
| projects[].tags | object | Tags assigned to the project. Can be simple string or key:value pair |
| projects[].repoUrl | string | The URL of the repo where the source code resides |
| projects[].mainBranch | string | The Git branch designated as "primary" for this project |
| projects[].origin | string | The SCM from which this project was created (e.g. GitHub, GitLab). Empty for manual projects |
| projects[].criticality | integer | Criticality level of the project |
| projects[].privatePackage | boolean | If true, package is handled as private by the SCA scanner (not yet supported) |
| projects[].imported_proj_name | string | For migrated projects, shows the repo name from the original project |
| projects[].scmRepoId | string | For internal Checkmarx use |
| projects[].repoId | integer | For internal Checkmarx use |

## Error Responses

| Status | Description |
|--------|-------------|
| 400 | Bad Request |
| 401 | Not Authorized |
| 403 | Forbidden |
