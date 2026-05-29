from pydantic import BaseModel, Field
from typing import Any

class TriageRequest(BaseModel):
    wazuh: dict[str, Any] = Field(default_factory=dict)
    cti: dict[str, Any] = Field(default_factory=dict)
