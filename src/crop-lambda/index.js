const { S3Client, GetObjectCommand, PutObjectCommand } = require("@aws-sdk/client-s3");
const sharp = require("sharp");

const s3Client = new S3Client({});

// Función para leer el archivo de S3
const streamToBuffer = (stream) => {
    return new Promise((resolve, reject) => {
        const chunks = [];
        stream.on("data", (chunk) => chunks.push(chunk));
        stream.on("error", reject);
        stream.on("end", () => resolve(Buffer.concat(chunks)));
    });
};

exports.handler = async (event) => {
    for (const record of event.Records) {
        try {
            // Extraer datos del evento SQS -> S3
            const messageBody = JSON.parse(record.body);
            const s3Event = messageBody.Records[0];
            
            const sourceBucket = s3Event.s3.bucket.name;
            const sourceKey = decodeURIComponent(s3Event.s3.object.key.replace(/\+/g, " "));
            
            const destBucket = process.env.S3_BUCKET;
            const destPrefix = process.env.PROCESSED_PREFIX; // "processed/"
            const fileName = sourceKey.split('/').pop();
            const destKey = `${destPrefix}circular_${fileName}`;

            // Descargar la imagen
            const getCmd = new GetObjectCommand({ Bucket: sourceBucket, Key: sourceKey });
            const s3Response = await s3Client.send(getCmd);
            const imageBuffer = await streamToBuffer(s3Response.Body);

            // Recorte circular a 40x40 usando Sharp
            const circleSvg = `<svg width="40" height="40"><circle cx="20" cy="20" r="20" /></svg>`;
            const processedBuffer = await sharp(imageBuffer)
                .resize(40, 40)
                .composite([{ input: Buffer.from(circleSvg), blend: 'dest-in' }])
                .png()
                .toBuffer();

            // Guardar la imagen procesada
            const putCmd = new PutObjectCommand({
                Bucket: destBucket,
                Key: destKey,
                Body: processedBuffer,
                ContentType: "image/png"
            });
            await s3Client.send(putCmd);

        } catch (error) {
            console.error("Fallo al procesar imagen:", error);
            // Estrategia de Failover (Tolerancia a fallos)
            throw error; 
        }
    }
};