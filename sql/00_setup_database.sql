:setvar DemoDatabase "CustomerAIDemo"

IF DB_ID(N'$(DemoDatabase)') IS NULL
BEGIN
    EXEC(N'CREATE DATABASE [$(DemoDatabase)]');
END
GO

USE [$(DemoDatabase)];
GO

-- SQL Server 2025 vector features are preview features.
ALTER DATABASE SCOPED CONFIGURATION
SET PREVIEW_FEATURES = ON;
GO

-- SQL Server 2025 compatibility level. Comment this line if your preview build
-- does not expose compatibility level 170 yet.
BEGIN TRY
    ALTER DATABASE [$(DemoDatabase)] SET COMPATIBILITY_LEVEL = 170;
END TRY
BEGIN CATCH
    PRINT 'Could not set compatibility level 170 on this build. Continuing.';
END CATCH;
GO

