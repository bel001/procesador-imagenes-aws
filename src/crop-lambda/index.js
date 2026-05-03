const { S3Client, GetObjectCommand, PutObjectCommand } = require("@aws-sdk/client-s3");
const sharp = require("sharp");
const path = require("path");

const s3 = new S3Client({});
const BUCKET_NAME = process.env.S3_BUCKET;
const PROCESSED_PREFIX = process.env.PROCESSED_PREFIX || "processed/";

exports.handler = async (event) => {
    for (const record of event.Records) {
        const body = JSON.parse(record.body);
        if (!body.Records) continue;

        for (const s3Record of body.Records) {
            const originalKey = decodeURIComponent(s3Record.s3.object.key.replace(/\+/g, " "));
            
            // 1. Descargar imagen
            const getCmd = new GetObjectCommand({ Bucket: BUCKET_NAME, Key: originalKey });
            const response = await s3.send(getCmd);
            const imageBytes = await response.Body.transformToByteArray();

            // 2. Crear mascara SVG circular de 40x40
            const circleSvg = `<svg width="40" height="40"><circle cx="20" cy="20" r="20" fill="white"/></svg>`;

            // 3. Procesar con Sharp (Cover 40x40 + Mascara Circular + PNG Alfa)
            const processedBuffer = await sharp(Buffer.from(imageBytes))
                .resize(40, 40, { fit: 'cover' })
                .composite([{
                    input: Buffer.from(circleSvg),
                    blend: 'dest-in'
                }])
                .png()
                .toBuffer();

            // 4. Renombrar
            const parsedPath = path.parse(originalKey);
            const filenameWithoutPrefix = parsedPath.name.replace("uploads/", "");
            const newKey = `${PROCESSED_PREFIX}${filenameWithoutPrefix}_circular.png`;

            // 5. Subir imagen procesada
            const putCmd = new PutObjectCommand({
                Bucket: BUCKET_NAME,
                Key: newKey,
                Body: processedBuffer,
                ContentType: "image/png"
            });
            await s3.send(putCmd);
        }
    }
    return { statusCode: 200, body: "Procesado correctamente" };
};