import os
import sys
import logging
from dotenv import load_dotenv
import snowflake.connector

# Set up logging configuration
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Load credentials from .env
load_dotenv()

def get_snowflake_connection():
    """Establishes and returns a secure connection to Snowflake."""
    try:
        return snowflake.connector.connect(
            user=os.getenv("SF_USER"),
            password=os.getenv("SF_PASSWORD"),
            account=os.getenv("SF_ACCOUNT"),
            warehouse=os.getenv("SF_WAREHOUSE"),
            database=os.getenv("SF_DATABASE"),
            role=os.getenv("SF_ROLE")
        )
    except Exception as e:
        logger.error(f"Failed to connect to Snowflake: {e}")
        sys.exit(1)

def read_sql_file(file_name):
    """Reads a SQL query from the /sql folder using safe relative paths."""
    # Find the directory of this current script, then look for the /sql folder
    base_dir = os.path.dirname(os.path.abspath(__file__))
    file_path = os.path.join(base_dir, "sql", file_name)
    
    try:
        with open(file_path, "r", encoding="utf-8") as file:
            return file.read()
    except FileNotFoundError:
        logger.error(f"Required SQL file not found: {file_path}")
        sys.exit(1)
    except Exception as e:
        logger.error(f"Error reading file {file_path}: {e}")
        sys.exit(1)

def run_query(cursor, query_description, sql_query):
    """Helper function to execute a query and log progress."""
    logger.info(f"Starting: {query_description}...")
    try:
        cursor.execute(sql_query)
        logger.info(f"Completed: {query_description}")
    except Exception as e:
        logger.error(f"CRITICAL ERROR during '{query_description}': {e}")
        raise e

def main():
    # 1. Load SQL contents dynamically from files
    sql_staging_prescribers = read_sql_file("stage_2_1_staging_prescribers.sql")
    sql_staging_claims = read_sql_file("stage_2_2_staging_claims.sql")
    sql_scd_expire = read_sql_file("stage_7_1_scd_expire.sql")
    sql_scd_insert = read_sql_file("stage_7_2_scd_insert.sql")
    sql_dq_checks = read_sql_file("stage_5_1_dq_checks.sql")

    # 2. Establish Snowflake Connection
    conn = get_snowflake_connection()
    logger.info("Connection established successfully.")

    try:
        with conn.cursor() as cursor:
            # Step A: Run Staging Cleanse
            run_query(cursor, "Stage 2.1 — Building Staging Providers", sql_staging_prescribers)
            run_query(cursor, "Stage 2.2 — Building Staging Claims", sql_staging_claims)

            # Step B: Execute Slowly Changing Dimension (SCD Type 2) transaction
            run_query(cursor, "Stage 7.1 — Expiring Historical Provider Records", sql_scd_expire)
            run_query(cursor, "Stage 7.2 — Appending Active Provider Records", sql_scd_insert)

            # Step C: Log Data Quality Checks
            run_query(cursor, "Stage 5.1 — Logging Row Reconciliation Audits", sql_dq_checks)

        # Commit all actions if the script runs error-free
        conn.commit()
        logger.info("Pipeline completed and transaction committed successfully.")

    except Exception as e:
        logger.error("Pipeline encountered an issue. Executing Rollback.")
        conn.rollback()
        sys.exit(1)

    finally:
        conn.close()
        logger.info("Snowflake connection closed safely.")

if __name__ == "__main__":
    main()