from pydantic import AliasChoices, Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_prefix="RELIEFLINK_", extra="ignore")

    port: int = 8000
    admin_pin: str = "1234"
    mongo_url: str = "mongodb://localhost:27017"
    mongo_db: str = "relieflink"
    # Accept both OLLAMA_BASE_URL and RELIEFLINK_OLLAMA_BASE_URL. No IP is hardcoded.
    ollama_base_url: str = Field(
        default="http://localhost:11434",
        validation_alias=AliasChoices("OLLAMA_BASE_URL", "RELIEFLINK_OLLAMA_BASE_URL"))
    ollama_model: str = Field(
        default="",
        validation_alias=AliasChoices("OLLAMA_MODEL", "RELIEFLINK_OLLAMA_MODEL"))


settings = Settings()
