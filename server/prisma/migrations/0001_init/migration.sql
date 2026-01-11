-- CreateSchema
CREATE SCHEMA IF NOT EXISTS "public";

-- CreateTable
CREATE TABLE "EventLog" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "deviceId" TEXT NOT NULL,
    "entityType" TEXT NOT NULL,
    "entityId" TEXT NOT NULL,
    "op" TEXT NOT NULL,
    "payload" JSONB NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "schemaVersion" INTEGER NOT NULL,

    CONSTRAINT "EventLog_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ReadingPosition" (
    "userId" TEXT NOT NULL,
    "bookId" TEXT NOT NULL,
    "chapterHref" TEXT,
    "anchor" TEXT,
    "offset" INTEGER,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "ReadingPosition_pkey" PRIMARY KEY ("userId","bookId")
);

-- CreateTable
CREATE TABLE "SyncCursor" (
    "userId" TEXT NOT NULL,
    "deviceId" TEXT NOT NULL,
    "lastCursor" TEXT NOT NULL,
    "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "SyncCursor_pkey" PRIMARY KEY ("userId","deviceId")
);

-- CreateIndex
CREATE INDEX "EventLog_userId_createdAt_idx" ON "EventLog"("userId", "createdAt");

-- CreateIndex
CREATE INDEX "EventLog_userId_entityType_entityId_idx" ON "EventLog"("userId", "entityType", "entityId");

-- CreateIndex
CREATE INDEX "ReadingPosition_userId_updatedAt_idx" ON "ReadingPosition"("userId", "updatedAt");

