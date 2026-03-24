-- =============================================================================
-- SPECTRA / BOSS Read-Only Data Store — Config Table UPDATE Statements
-- Column   : advanced_query_template1
-- Quoting  : Oracle q'{ }' syntax — no escape needed
-- Placeholder: ##LAST_RUN_TS## replaced at runtime via REPLACE() in PL/SQL
--              e.g. l_query := REPLACE(advanced_query_template1,
--                                      '##LAST_RUN_TS##',
--                                      TO_CHAR(l_last_run_ts, 'YYYY-MM-DD"T"HH24:MI:SS"Z"'));
-- Fields   : ALL fields per Oracle 26A documentation for each view + all accessors
-- Generated: 2026-03-24
-- =============================================================================
-- NOTE: Replace xxint_spectra_config and view_code values to match your table
-- =============================================================================


-- =============================================================================
-- MODULE 1: Global HR - Employment
-- Module Name         : oraHcmHrCoreEmployment
-- Module Context Path : hcmHrCore/employment
-- =============================================================================

-- 1. actionExtracts
UPDATE xxint_spectra_config
SET    boss_module               = 'oraHcmHrCoreEmployment',
       boss_view_name            = 'actionExtracts',
       advanced_query_template1  = q'{
{
  "collection": {
    "filter": "timeUpdated > '##LAST_RUN_TS##'"
  },
  "fields": [
    "id",
    "actionCode",
    "startDate",
    "endDate",
    "timeCreated",
    "timeUpdated",
    "createdBy",
    "updatedBy",
    "actionName",
    "description"
  ]
}}'
WHERE  view_code = 'ACTION_EXTRACTS';


-- 2. assignmentStatusTypeExtracts
UPDATE xxint_spectra_config
SET    boss_module               = 'oraHcmHrCoreEmployment',
       boss_view_name            = 'assignmentStatusTypeExtracts',
       advanced_query_template1  = q'{
{
  "collection": {
    "filter": "timeUpdated > '##LAST_RUN_TS##'"
  },
  "fields": [
    "id",
    "assignmentStatusCode",
    "fromDate",
    "toDate",
    "activeFlag",
    "defaultFlag",
    "timeCreated",
    "timeUpdated",
    "createdBy",
    "updatedBy",
    "userStatus"
  ]
}}'
WHERE  view_code = 'ASSIGNMENT_STATUS_TYPE_EXTRACTS';


-- 3. emailExtracts
UPDATE xxint_spectra_config
SET    boss_module               = 'oraHcmHrCoreEmployment',
       boss_view_name            = 'emailExtracts',
       advanced_query_template1  = q'{
{
  "collection": {
    "filter": "timeUpdated > '##LAST_RUN_TS##'"
  },
  "fields": [
    "id",
    "fromDate",
    "toDate",
    "emailAddress",
    "timeUpdated",
    "updatedBy",
    "timeCreated",
    "createdBy",
    "primaryFlag"
  ],
  "accessors": {
    "personDetail": {
      "fields": [
        "id",
        "personNumber",
        "effectiveStartDate",
        "effectiveEndDate"
      ]
    },
    "type": {
      "fields": [
        "lookupCode",
        "lookupType",
        "meaning"
      ]
    }
  }
}}'
WHERE  view_code = 'EMAIL_EXTRACTS';


-- 4. legislativeInformationExtracts
UPDATE xxint_spectra_config
SET    boss_module               = 'oraHcmHrCoreEmployment',
       boss_view_name            = 'legislativeInformationExtracts',
       advanced_query_template1  = q'{
{
  "collection": {
    "filter": "timeUpdated > '##LAST_RUN_TS##'"
  },
  "fields": [
    "id",
    "effectiveStartDate",
    "effectiveEndDate",
    "gender",
    "maritalStatus",
    "maritalStatusChangeDate",
    "highestEducationLevel",
    "timeUpdated",
    "updatedBy",
    "timeCreated",
    "createdBy"
  ],
  "accessors": {
    "personDetail": {
      "fields": [
        "id",
        "personNumber",
        "effectiveStartDate",
        "effectiveEndDate"
      ]
    },
    "legislation": {
      "fields": [
        "territoryCode",
        "territoryShortName"
      ]
    }
  }
}}'
WHERE  view_code = 'LEGISLATIVE_INFO_EXTRACTS';


-- 5. legislativeInformationHistoryExtracts
UPDATE xxint_spectra_config
SET    boss_module               = 'oraHcmHrCoreEmployment',
       boss_view_name            = 'legislativeInformationHistoryExtracts',
       advanced_query_template1  = q'{
{
  "collection": {
    "filter": "timeUpdated > '##LAST_RUN_TS##'"
  },
  "fields": [
    "id",
    "effectiveStartDate",
    "effectiveEndDate",
    "gender",
    "maritalStatus",
    "maritalStatusChangeDate",
    "highestEducationLevel",
    "timeUpdated",
    "updatedBy",
    "timeCreated",
    "createdBy"
  ],
  "accessors": {
    "personDetail": {
      "fields": [
        "id",
        "personNumber"
      ]
    },
    "legislation": {
      "fields": [
        "territoryCode",
        "territoryShortName"
      ]
    }
  }
}}'
WHERE  view_code = 'LEGISLATIVE_INFO_HISTORY_EXTRACTS';


-- 6. managerHierarchyExtracts
UPDATE xxint_spectra_config
SET    boss_module               = 'oraHcmHrCoreEmployment',
       boss_view_name            = 'managerHierarchyExtracts',
       advanced_query_template1  = q'{
{
  "collection": {
    "filter": "timeUpdated > '##LAST_RUN_TS##'"
  },
  "fields": [
    "effectiveStartDate",
    "effectiveEndDate",
    "personId",
    "assignmentId",
    "managerType",
    "managerLevel",
    "managerId",
    "managerAssignmentId",
    "primaryAssignmentFlag",
    "primaryManagerFlag",
    "createdBy",
    "timeCreated",
    "updatedBy",
    "timeUpdated"
  ],
  "accessors": {
    "personAssignment": {
      "fields": [
        "id",
        "effectiveStartDate",
        "effectiveEndDate",
        "effectiveSequence",
        "effectiveLatestChange",
        "assignmentType",
        "assignmentNumber",
        "primaryFlag",
        "businessTitle",
        "workAtHomeFlag",
        "officeBuilding",
        "officeFloor",
        "officeMailStop",
        "officeNumber",
        "primaryAssignmentFlag",
        "primaryWorkRelationshipFlag",
        "timeUpdated",
        "updatedBy",
        "timeCreated",
        "createdBy",
        "systemPersonType",
        "labourUnionMemberFlag",
        "managerFlag",
        "probationEndDate",
        "probationPeriod",
        "probationPeriodUnit",
        "normalHours",
        "frequency",
        "endTime",
        "startTime",
        "noticePeriod",
        "noticePeriodUOM",
        "workerCategory",
        "assignmentCategory",
        "hourlyPaidOrSalaried",
        "projectedEndDate",
        "projectedStartDate",
        "assignmentStatusType",
        "retirementAge",
        "retirementDate",
        "synchronizeFromPositionFlag",
        "fullTimeOrPartTime",
        "permanentAssignmentFlag",
        "seniorityBasis",
        "overtimePeriod",
        "adjustedFullTimeEquivalent",
        "annualWorkingDuration",
        "annualWorkingDurationUnit",
        "annualWorkingRatio",
        "standardFrequency",
        "standardWorkingHours",
        "standardAnnualWorkingDuration",
        "sequence"
      ],
      "accessors": {
        "department": {
          "fields": [ "id", "name", "title", "effectiveStartDate", "effectiveEndDate" ]
        },
        "legalEmployer": {
          "fields": [ "id", "name", "effectiveStartDate", "effectiveEndDate" ]
        },
        "legislation": {
          "fields": [ "territoryCode", "territoryShortName" ]
        },
        "position": {
          "fields": [ "id", "effectiveStartDate", "effectiveEndDate", "name", "code" ]
        },
        "grade": {
          "fields": [ "id", "effectiveStartDate", "effectiveEndDate", "name", "code" ]
        },
        "location": {
          "fields": [ "id", "effectiveStartDate", "effectiveEndDate", "name", "code" ],
          "accessors": {
            "mainAddress": {
              "fields": [
                "id", "effectiveStartDate", "effectiveEndDate",
                "county", "state", "province", "townOrCity",
                "postalCode", "longPostalCode",
                "addressLine1", "addressLine2", "addressLine3", "addressLine4"
              ],
              "accessors": {
                "country": {
                  "fields": [ "territoryCode", "territoryShortName" ]
                }
              }
            }
          }
        },
        "job": {
          "fields": [ "id", "effectiveStartDate", "effectiveEndDate", "name", "code", "jobFunctionCode", "managerLevel" ],
          "accessors": {
            "jobFamily": {
              "fields": [ "id", "effectiveStartDate", "effectiveEndDate", "code", "name" ]
            }
          }
        },
        "collectiveAgreement": {
          "fields": [ "id", "effectiveStartDate", "effectiveEndDate", "name" ]
        },
        "personType": {
          "fields": [ "id", "userPersonType" ]
        },
        "workerUnion": {
          "fields": [ "id", "effectiveStartDate", "effectiveEndDate", "name" ]
        },
        "assignmentUserStatus": {
          "fields": [ "id", "userStatus" ]
        },
        "businessUnit": {
          "fields": [ "id", "effectiveStartDate", "effectiveEndDate", "name" ]
        },
        "account": {
          "fields": [ "codeCombinationId", "concatenatedSegments", "chartOfAccountsId" ]
        },
        "ledger": {
          "fields": [ "ledgerId", "name" ]
        },
        "workRelationship": {
          "fields": [ "id", "startDate", "workerType", "timeCreated", "timeUpdated" ]
        },
        "localName": {
          "fields": [ "id", "effectiveStartDate", "effectiveEndDate", "lastName", "firstName", "displayName", "listName", "timeCreated", "timeUpdated" ]
        },
        "globalName": {
          "fields": [ "id", "effectiveStartDate", "effectiveEndDate", "lastName", "firstName", "displayName", "listName", "timeCreated", "timeUpdated" ]
        },
        "personDetail": {
          "fields": [ "id", "personNumber", "effectiveStartDate", "effectiveEndDate", "timeCreated", "timeUpdated" ]
        }
      }
    }
  }
}}'
WHERE  view_code = 'MANAGER_HIERARCHY_EXTRACTS';


-- 7. nameExtracts
UPDATE xxint_spectra_config
SET    boss_module               = 'oraHcmHrCoreEmployment',
       boss_view_name            = 'nameExtracts',
       advanced_query_template1  = q'{
{
  "collection": {
    "filter": "timeUpdated > '##LAST_RUN_TS##'"
  },
  "fields": [
    "id",
    "effectiveStartDate",
    "effectiveEndDate",
    "lastname",
    "firstname",
    "middlenames",
    "title",
    "prefix",
    "suffix",
    "knownAs",
    "previousLastname",
    "honors",
    "militaryRank",
    "displayname",
    "fullname",
    "listname",
    "ordername",
    "type",
    "timeUpdated",
    "updatedBy",
    "timeCreated",
    "createdBy"
  ],
  "accessors": {
    "personDetail": {
      "fields": [
        "id",
        "personNumber",
        "effectiveStartDate",
        "effectiveEndDate"
      ]
    },
    "legislation": {
      "fields": [
        "territoryCode",
        "territoryShortname"
      ]
    }
  }
}}'
WHERE  view_code = 'NAME_EXTRACTS';


-- 8. nationalIdentifierExtracts
UPDATE xxint_spectra_config
SET    boss_module               = 'oraHcmHrCoreEmployment',
       boss_view_name            = 'nationalIdentifierExtracts',
       advanced_query_template1  = q'{
{
  "collection": {
    "filter": "timeUpdated > '##LAST_RUN_TS##'"
  },
  "fields": [
    "id",
    "createdBy",
    "expirationDate",
    "issueDate",
    "identifierNumber",
    "placeOfIssue",
    "timeCreated",
    "timeUpdated",
    "updatedBy"
  ],
  "accessors": {
    "personDetail": {
      "fields": [
        "id",
        "personNumber",
        "effectiveStartDate",
        "effectiveEndDate"
      ]
    },
    "country": {
      "fields": [
        "territoryCode",
        "territoryShortName"
      ]
    },
    "type": {
      "fields": [
        "lookupCode",
        "lookupType",
        "meaning"
      ]
    }
  }
}}'
WHERE  view_code = 'NATIONAL_IDENTIFIER_EXTRACTS';


-- 9. personAddressExtracts
UPDATE xxint_spectra_config
SET    boss_module               = 'oraHcmHrCoreEmployment',
       boss_view_name            = 'personAddressExtracts',
       advanced_query_template1  = q'{
{
  "collection": {
    "filter": "timeUpdated > '##LAST_RUN_TS##'"
  },
  "fields": [
    "id",
    "effectiveStartDate",
    "effectiveEndDate",
    "type",
    "primaryFlag",
    "timeCreated",
    "timeUpdated",
    "createdBy",
    "updatedBy",
    "building",
    "floorNumber",
    "townOrCity",
    "postalCode",
    "longPostalCode",
    "addressLine1",
    "addressLine2",
    "addressLine3",
    "addressLine4",
    "county",
    "state",
    "province"
  ],
  "accessors": {
    "personDetail": {
      "fields": [
        "id",
        "personNumber",
        "effectiveStartDate",
        "effectiveEndDate"
      ]
    },
    "country": {
      "fields": [
        "territoryCode",
        "territoryShortName"
      ]
    }
  }
}}'
WHERE  view_code = 'PERSON_ADDRESS_EXTRACTS';


-- 10. personAddressHistoryExtracts
UPDATE xxint_spectra_config
SET    boss_module               = 'oraHcmHrCoreEmployment',
       boss_view_name            = 'personAddressHistoryExtracts',
       advanced_query_template1  = q'{
{
  "collection": {
    "filter": "timeUpdated > '##LAST_RUN_TS##'"
  },
  "fields": [
    "id",
    "effectiveStartDate",
    "effectiveEndDate",
    "type",
    "primaryFlag",
    "timeCreated",
    "timeUpdated",
    "createdBy",
    "updatedBy",
    "building",
    "floorNumber",
    "townOrCity",
    "postalCode",
    "longPostalCode",
    "addressLine1",
    "addressLine2",
    "addressLine3",
    "addressLine4",
    "county",
    "state",
    "province"
  ],
  "accessors": {
    "country": {
      "fields": [
        "territoryCode",
        "territoryShortName"
      ]
    }
  }
}}'
WHERE  view_code = 'PERSON_ADDRESS_HISTORY_EXTRACTS';


-- 11. personTypeExtracts
UPDATE xxint_spectra_config
SET    boss_module               = 'oraHcmHrCoreEmployment',
       boss_view_name            = 'personTypeExtracts',
       advanced_query_template1  = q'{
{
  "collection": {
    "filter": "timeUpdated > '##LAST_RUN_TS##'"
  },
  "fields": [
    "id",
    "systemPersonType",
    "activeFlag",
    "defaultFlag",
    "timeCreated",
    "timeUpdated",
    "createdBy",
    "updatedBy",
    "userPersonType"
  ]
}}'
WHERE  view_code = 'PERSON_TYPE_EXTRACTS';


-- 12. phoneExtracts
UPDATE xxint_spectra_config
SET    boss_module               = 'oraHcmHrCoreEmployment',
       boss_view_name            = 'phoneExtracts',
       advanced_query_template1  = q'{
{
  "collection": {
    "filter": "timeUpdated > '##LAST_RUN_TS##'"
  },
  "fields": [
    "id",
    "fromDate",
    "toDate",
    "phoneNumber",
    "areaCode",
    "countryCodeNumber",
    "extension",
    "validity",
    "timeUpdated",
    "updatedBy",
    "timeCreated",
    "createdBy",
    "primaryFlag"
  ],
  "accessors": {
    "personDetail": {
      "fields": [
        "id",
        "personNumber",
        "effectiveStartDate",
        "effectiveEndDate"
      ]
    },
    "legislation": {
      "fields": [
        "territoryCode",
        "territoryShortName"
      ]
    },
    "type": {
      "fields": [
        "lookupCode",
        "lookupType",
        "meaning"
      ]
    }
  }
}}'
WHERE  view_code = 'PHONE_EXTRACTS';


-- 13. workerAssignmentExtracts
UPDATE xxint_spectra_config
SET    boss_module               = 'oraHcmHrCoreEmployment',
       boss_view_name            = 'workerAssignmentExtracts',
       advanced_query_template1  = q'{
{
  "collection": {
    "filter": "timeUpdated > '##LAST_RUN_TS##' and primaryFlag = true and assignmentType = 'E'"
  },
  "fields": [
    "id",
    "effectiveStartDate",
    "effectiveEndDate",
    "effectiveSequence",
    "effectiveLatestChange",
    "assignmentType",
    "assignmentNumber",
    "primaryFlag",
    "businessTitle",
    "workAtHomeFlag",
    "officeBuilding",
    "officeFloor",
    "officeMailStop",
    "officeNumber",
    "primaryAssignmentFlag",
    "primaryWorkRelationshipFlag",
    "timeUpdated",
    "updatedBy",
    "timeCreated",
    "createdBy",
    "systemPersonType",
    "labourUnionMemberFlag",
    "managerFlag",
    "probationEndDate",
    "probationPeriod",
    "probationPeriodUnit",
    "normalHours",
    "frequency",
    "endTime",
    "startTime",
    "noticePeriod",
    "noticePeriodUOM",
    "workerCategory",
    "assignmentCategory",
    "hourlyPaidOrSalaried",
    "projectedEndDate",
    "projectedStartDate",
    "assignmentStatusType",
    "expenseCheckSendToAddress",
    "retirementAge",
    "retirementDate",
    "synchronizeFromPositionFlag",
    "fullTimeOrPartTime",
    "permanentAssignmentFlag",
    "seniorityBasis",
    "overtimePeriod",
    "adjustedFullTimeEquivalent",
    "annualWorkingDuration",
    "annualWorkingDurationUnit",
    "annualWorkingRatio",
    "standardFrequency",
    "standardWorkingHours",
    "standardAnnualWorkingDuration",
    "sequence"
  ],
  "accessors": {
    "department": {
      "fields": [ "id", "name", "title", "effectiveStartDate", "effectiveEndDate" ]
    },
    "legalEmployer": {
      "fields": [ "id", "name", "effectiveStartDate", "effectiveEndDate" ]
    },
    "legislation": {
      "fields": [ "territoryCode", "territoryShortName" ]
    },
    "position": {
      "fields": [ "id", "effectiveStartDate", "effectiveEndDate", "name", "code" ]
    },
    "grade": {
      "fields": [ "id", "effectiveStartDate", "effectiveEndDate", "name", "code" ]
    },
    "location": {
      "fields": [ "id", "effectiveStartDate", "effectiveEndDate", "name", "code" ],
      "accessors": {
        "mainAddress": {
          "fields": [
            "id", "effectiveStartDate", "effectiveEndDate",
            "county", "state", "province", "townOrCity",
            "postalCode", "longPostalCode",
            "addressLine1", "addressLine2", "addressLine3", "addressLine4"
          ],
          "accessors": {
            "country": {
              "fields": [ "territoryCode", "territoryShortName" ]
            }
          }
        }
      }
    },
    "job": {
      "fields": [ "id", "effectiveStartDate", "effectiveEndDate", "name", "code", "jobFunctionCode", "managerLevel" ],
      "accessors": {
        "jobFamily": {
          "fields": [ "id", "effectiveStartDate", "effectiveEndDate", "code", "name" ]
        }
      }
    },
    "collectiveAgreement": {
      "fields": [ "id", "effectiveStartDate", "effectiveEndDate", "name" ]
    },
    "personType": {
      "fields": [ "id", "userPersonType" ]
    },
    "workerUnion": {
      "fields": [ "id", "effectiveStartDate", "effectiveEndDate", "name" ]
    },
    "assignmentUserStatus": {
      "fields": [ "id", "userStatus" ]
    },
    "businessUnit": {
      "fields": [ "id", "effectiveStartDate", "effectiveEndDate", "name" ]
    },
    "account": {
      "fields": [ "codeCombinationId", "concatenatedSegments", "chartOfAccountsId" ]
    },
    "ledger": {
      "fields": [ "ledgerId", "name" ]
    },
    "workRelationship": {
      "fields": [ "id", "startDate", "workerType", "timeCreated", "timeUpdated" ]
    },
    "localName": {
      "fields": [ "id", "effectiveStartDate", "effectiveEndDate", "lastName", "firstName", "displayName", "listName", "timeCreated", "timeUpdated" ]
    },
    "globalName": {
      "fields": [ "id", "effectiveStartDate", "effectiveEndDate", "lastName", "firstName", "displayName", "listName", "timeCreated", "timeUpdated" ]
    },
    "personDetail": {
      "fields": [ "id", "personNumber", "effectiveStartDate", "effectiveEndDate", "timeCreated", "timeUpdated" ]
    }
  }
}}'
WHERE  view_code = 'WORKER_ASSIGNMENT_EXTRACTS';


-- 14. workerAssignmentHistoryExtracts
UPDATE xxint_spectra_config
SET    boss_module               = 'oraHcmHrCoreEmployment',
       boss_view_name            = 'workerAssignmentHistoryExtracts',
       advanced_query_template1  = q'{
{
  "collection": {
    "filter": "timeUpdated > '##LAST_RUN_TS##' and primaryFlag = true"
  },
  "fields": [
    "id",
    "effectiveStartDate",
    "effectiveEndDate",
    "effectiveSequence",
    "effectiveLatestChange",
    "assignmentType",
    "assignmentNumber",
    "primaryFlag",
    "businessTitle",
    "workAtHomeFlag",
    "officeBuilding",
    "officeFloor",
    "officeMailStop",
    "officeNumber",
    "primaryAssignmentFlag",
    "primaryWorkRelationshipFlag",
    "timeUpdated",
    "updatedBy",
    "timeCreated",
    "createdBy",
    "systemPersonType",
    "labourUnionMemberFlag",
    "managerFlag",
    "probationEndDate",
    "probationPeriod",
    "probationPeriodUnit",
    "normalHours",
    "frequency",
    "endTime",
    "startTime",
    "noticePeriod",
    "noticePeriodUOM",
    "workerCategory",
    "assignmentCategory",
    "hourlyPaidOrSalaried",
    "projectedEndDate",
    "projectedStartDate",
    "assignmentStatusType",
    "expenseCheckSendToAddress",
    "retirementAge",
    "retirementDate",
    "synchronizeFromPositionFlag",
    "fullTimeOrPartTime",
    "permanentAssignmentFlag",
    "seniorityBasis",
    "overtimePeriod",
    "adjustedFullTimeEquivalent",
    "annualWorkingDuration",
    "annualWorkingDurationUnit",
    "annualWorkingRatio",
    "standardFrequency",
    "standardWorkingHours",
    "standardAnnualWorkingDuration",
    "sequence"
  ],
  "accessors": {
    "department": {
      "fields": [ "id" ]
    },
    "legalEmployer": {
      "fields": [ "id" ]
    },
    "legislation": {
      "fields": [ "territoryCode", "territoryShortName" ]
    },
    "position": {
      "fields": [ "id" ]
    },
    "grade": {
      "fields": [ "id" ]
    },
    "location": {
      "fields": [ "id" ],
      "accessors": {
        "mainAddress": {
          "fields": [ "id" ],
          "accessors": {
            "country": {
              "fields": [ "territoryCode", "territoryShortName" ]
            }
          }
        }
      }
    },
    "job": {
      "fields": [ "id" ],
      "accessors": {
        "jobFamily": {
          "fields": [ "id" ]
        }
      }
    },
    "collectiveAgreement": {
      "fields": [ "id" ]
    },
    "personType": {
      "fields": [ "id", "userPersonType" ]
    },
    "workerUnion": {
      "fields": [ "id" ]
    },
    "assignmentUserStatus": {
      "fields": [ "id", "userStatus" ]
    },
    "businessUnit": {
      "fields": [ "id" ]
    },
    "account": {
      "fields": [ "codeCombinationId", "concatenatedSegments", "chartOfAccountsId" ]
    },
    "ledger": {
      "fields": [ "ledgerId", "name" ]
    },
    "workRelationship": {
      "fields": [ "id" ]
    },
    "localName": {
      "fields": [ "id" ]
    },
    "globalName": {
      "fields": [ "id" ]
    },
    "personDetail": {
      "fields": [ "id", "personNumber" ]
    }
  }
}}'
WHERE  view_code = 'WORKER_ASSIGNMENT_HISTORY_EXTRACTS';


-- 15. workRelationshipExtracts
UPDATE xxint_spectra_config
SET    boss_module               = 'oraHcmHrCoreEmployment',
       boss_view_name            = 'workRelationshipExtracts',
       advanced_query_template1  = q'{
{
  "collection": {
    "filter": "timeUpdated > '##LAST_RUN_TS##'"
  },
  "fields": [
    "id",
    "startDate",
    "workerType",
    "timeCreated",
    "timeUpdated",
    "workerNumber",
    "primaryFlag",
    "createdBy",
    "updatedBy",
    "readyToConvertFlag",
    "enterpriseSeniorityDate",
    "legalEmployerSeniorityDate",
    "onMilitaryServiceFlag",
    "lastWorkingDate",
    "terminationDate",
    "notificationDate",
    "projectedTerminationDate"
  ],
  "accessors": {
    "legalEmployer": {
      "fields": [ "id", "name", "effectiveStartDate", "effectiveEndDate" ]
    },
    "legislation": {
      "fields": [ "territoryCode", "territoryShortName" ]
    },
    "personDetail": {
      "fields": [ "id", "personNumber", "effectiveStartDate", "effectiveEndDate" ]
    }
  }
}}'
WHERE  view_code = 'WORK_RELATIONSHIP_EXTRACTS';


-- =============================================================================
-- MODULE 2: Global HR - Work Structures
-- Module Name         : oraHcmHrCoreWorkStructures
-- Module Context Path : hcmHrCore/workStructures
-- =============================================================================

-- 16. gradeExtracts
UPDATE xxint_spectra_config
SET    boss_module               = 'oraHcmHrCoreWorkStructures',
       boss_view_name            = 'gradeExtracts',
       advanced_query_template1  = q'{
{
  "collection": {
    "filter": "timeUpdated > '##LAST_RUN_TS##'"
  },
  "fields": [
    "id",
    "createdBy",
    "effectiveStartDate",
    "effectiveEndDate",
    "code",
    "timeCreated",
    "timeUpdated",
    "updatedBy",
    "status",
    "name"
  ]
}}'
WHERE  view_code = 'GRADE_EXTRACTS';


-- 17. gradeHistoryExtracts
UPDATE xxint_spectra_config
SET    boss_module               = 'oraHcmHrCoreWorkStructures',
       boss_view_name            = 'gradeHistoryExtracts',
       advanced_query_template1  = q'{
{
  "collection": {
    "filter": "timeUpdated > '##LAST_RUN_TS##'"
  },
  "fields": [
    "id",
    "createdBy",
    "effectiveStartDate",
    "effectiveEndDate",
    "code",
    "timeCreated",
    "timeUpdated",
    "updatedBy",
    "status",
    "name"
  ]
}}'
WHERE  view_code = 'GRADE_HISTORY_EXTRACTS';


-- 18. jobExtracts
UPDATE xxint_spectra_config
SET    boss_module               = 'oraHcmHrCoreWorkStructures',
       boss_view_name            = 'jobExtracts',
       advanced_query_template1  = q'{
{
  "collection": {
    "filter": "timeUpdated > '##LAST_RUN_TS##'"
  },
  "fields": [
    "id",
    "name",
    "effectiveStartDate",
    "effectiveEndDate",
    "code",
    "status",
    "createdBy",
    "timeCreated",
    "updatedBy",
    "timeUpdated"
  ]
}}'
WHERE  view_code = 'JOB_EXTRACTS';


-- 19. jobFamilyExtracts
UPDATE xxint_spectra_config
SET    boss_module               = 'oraHcmHrCoreWorkStructures',
       boss_view_name            = 'jobFamilyExtracts',
       advanced_query_template1  = q'{
{
  "collection": {
    "filter": "timeUpdated > '##LAST_RUN_TS##'"
  },
  "fields": [
    "id",
    "code",
    "name",
    "effectiveStartDate",
    "effectiveEndDate",
    "status",
    "timeUpdated",
    "updatedBy",
    "timeCreated",
    "createdBy"
  ]
}}'
WHERE  view_code = 'JOB_FAMILY_EXTRACTS';


-- 20. jobFamilyHistoryExtracts
UPDATE xxint_spectra_config
SET    boss_module               = 'oraHcmHrCoreWorkStructures',
       boss_view_name            = 'jobFamilyHistoryExtracts',
       advanced_query_template1  = q'{
{
  "collection": {
    "filter": "timeUpdated > '##LAST_RUN_TS##'"
  },
  "fields": [
    "id",
    "code",
    "name",
    "effectiveStartDate",
    "effectiveEndDate",
    "status",
    "timeUpdated",
    "updatedBy",
    "timeCreated",
    "createdBy"
  ]
}}'
WHERE  view_code = 'JOB_FAMILY_HISTORY_EXTRACTS';


-- 21. jobHistoryExtracts
UPDATE xxint_spectra_config
SET    boss_module               = 'oraHcmHrCoreWorkStructures',
       boss_view_name            = 'jobHistoryExtracts',
       advanced_query_template1  = q'{
{
  "collection": {
    "filter": "timeUpdated > '##LAST_RUN_TS##'"
  },
  "fields": [
    "id",
    "name",
    "effectiveStartDate",
    "effectiveEndDate",
    "code",
    "status",
    "createdBy",
    "timeCreated",
    "updatedBy",
    "timeUpdated"
  ]
}}'
WHERE  view_code = 'JOB_HISTORY_EXTRACTS';


-- 22. locationExtracts
UPDATE xxint_spectra_config
SET    boss_module               = 'oraHcmHrCoreWorkStructures',
       boss_view_name            = 'locationExtracts',
       advanced_query_template1  = q'{
{
  "collection": {
    "filter": "timeUpdated > '##LAST_RUN_TS##'"
  },
  "fields": [
    "id",
    "createdBy",
    "effectiveStartDate",
    "effectiveEndDate",
    "code",
    "timeCreated",
    "timeUpdated",
    "updatedBy",
    "status",
    "countryCode",
    "employeeLocationFlag",
    "shipToSiteFlag",
    "receivingSiteFlag",
    "billToSiteFlag",
    "officeSiteFlag",
    "detailCreatedBy",
    "detailTimeCreated",
    "detailUpdatedBy",
    "detailTimeUpdated",
    "timezoneCode",
    "description",
    "name"
  ]
}}'
WHERE  view_code = 'LOCATION_EXTRACTS';


-- 23. locationHistoryExtracts
UPDATE xxint_spectra_config
SET    boss_module               = 'oraHcmHrCoreWorkStructures',
       boss_view_name            = 'locationHistoryExtracts',
       advanced_query_template1  = q'{
{
  "collection": {
    "filter": "timeUpdated > '##LAST_RUN_TS##'"
  },
  "fields": [
    "id",
    "createdBy",
    "effectiveStartDate",
    "effectiveEndDate",
    "code",
    "timeCreated",
    "timeUpdated",
    "updatedBy",
    "status",
    "countryCode",
    "employeeLocationFlag",
    "shipToSiteFlag",
    "receivingSiteFlag",
    "billToSiteFlag",
    "officeSiteFlag",
    "detailCreatedBy",
    "detailTimeCreated",
    "detailUpdatedBy",
    "detailTimeUpdated",
    "timezoneCode",
    "description",
    "name"
  ]
}}'
WHERE  view_code = 'LOCATION_HISTORY_EXTRACTS';


-- 24. positionExtracts
UPDATE xxint_spectra_config
SET    boss_module               = 'oraHcmHrCoreWorkStructures',
       boss_view_name            = 'positionExtracts',
       advanced_query_template1  = q'{
{
  "collection": {
    "filter": "timeUpdated > '##LAST_RUN_TS##'"
  },
  "fields": [
    "id",
    "effectiveStartDate",
    "effectiveEndDate",
    "code",
    "status",
    "hiringStatus",
    "createdBy",
    "timeCreated",
    "updatedBy",
    "timeUpdated",
    "name"
  ]
}}'
WHERE  view_code = 'POSITION_EXTRACTS';


-- 25. positionHistoryExtracts
UPDATE xxint_spectra_config
SET    boss_module               = 'oraHcmHrCoreWorkStructures',
       boss_view_name            = 'positionHistoryExtracts',
       advanced_query_template1  = q'{
{
  "collection": {
    "filter": "timeUpdated > '##LAST_RUN_TS##'"
  },
  "fields": [
    "id",
    "effectiveStartDate",
    "effectiveEndDate",
    "code",
    "status",
    "hiringStatus",
    "createdBy",
    "timeCreated",
    "updatedBy",
    "timeUpdated",
    "name"
  ]
}}'
WHERE  view_code = 'POSITION_HISTORY_EXTRACTS';


-- =============================================================================
-- MODULE 3: HCM Common - Events
-- Module Name         : oraHcmHrCoreEvents
-- Module Context Path : hcmHrCore/events
-- =============================================================================

-- 26. objectChangeExtracts
UPDATE xxint_spectra_config
SET    boss_module               = 'oraHcmHrCoreEvents',
       boss_view_name            = 'objectChangeExtracts',
       advanced_query_template1  = q'{
{
  "collection": {
    "filter": "timeUpdated > '##LAST_RUN_TS##' and changeComponents[physicalType = 'UPDATE']"
  },
  "fields": [
    "id",
    "sourceObjectName",
    "groupSequence",
    "operationType",
    "dateEffectiveMode",
    "effectiveDate",
    "keyAttribute1Name",
    "keyAttribute1DataType",
    "keyAttribute1StringValue",
    "keyAttribute1NumberValue",
    "keyAttribute1DateValue",
    "keyAttribute2Name",
    "keyAttribute2DataType",
    "keyAttribute2StringValue",
    "keyAttribute2NumberValue",
    "keyAttribute2DateValue",
    "keyAttribute3Name",
    "keyAttribute3DataType",
    "keyAttribute3StringValue",
    "keyAttribute3NumberValue",
    "keyAttribute3DateValue",
    "purgeDate",
    "createdBy",
    "timeCreated",
    "updatedBy",
    "timeUpdated"
  ],
  "accessors": {
    "changeComponents": {
      "collection": {
        "filter": "physicalType = 'UPDATE'"
      },
      "fields": [
        "id",
        "physicalType",
        "logicalType",
        "oldEffectiveStartDate",
        "newEffectiveStartDate",
        "oldEffectiveEndDate",
        "newEffectiveEndDate",
        "oldEffectiveSequence",
        "newEffectiveSequence",
        "createdBy",
        "timeCreated",
        "updatedBy",
        "timeUpdated"
      ],
      "accessors": {
        "changedAttributes": {
          "fields": [ "changedAttributesXml" ]
        }
      }
    }
  }
}}'
WHERE  view_code = 'OBJECT_CHANGE_EXTRACTS';


-- =============================================================================
-- COMMIT
-- =============================================================================
COMMIT;


-- =============================================================================
-- RUNTIME SUBSTITUTION PATTERN (reference — use in your procedure)
-- =============================================================================
/*
DECLARE
    l_query   CLOB;
    l_last_ts VARCHAR2(30);
BEGIN
    -- Format: YYYY-MM-DDThh:mm:ssZ
    l_last_ts := TO_CHAR(your_last_run_date, 'YYYY-MM-DD"T"HH24:MI:SS"Z"');

    SELECT advanced_query_template1
    INTO   l_query
    FROM   xxint_spectra_config
    WHERE  view_code = 'WORKER_ASSIGNMENT_EXTRACTS';

    l_query := REPLACE(l_query, '##LAST_RUN_TS##', l_last_ts);

    -- l_query is now ready to pass as boss.advancedQuery
END;
*/

-- =============================================================================
-- VERIFICATION
-- =============================================================================
/*
SELECT view_code,
       boss_module,
       boss_view_name,
       LENGTH(advanced_query_template1) AS query_length
FROM   xxint_spectra_config
WHERE  boss_module IN (
           'oraHcmHrCoreEmployment',
           'oraHcmHrCoreWorkStructures',
           'oraHcmHrCoreEvents'
       )
ORDER BY boss_module, boss_view_name;
*/
