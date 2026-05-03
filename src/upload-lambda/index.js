const { S3Client, PutObjectCommand } = require("@aws-sdk/client-s3");
const Busboy = require("busboy");
const { v4: uuidv4 } = require("uuid");

const s3 = new S3Client({});
const BUCKET_NAME = process.env.S3_BUCKET;
const PREFIX = process.env.UPLOAD_PREFIX || "uploads/";

exports.handler = async (event) => {
    return new Promise((resolve) => {
        const contentType = event.headers['content-type'] || event.headers['Content-Type'];
        let imageBuffer = null;
        let filename = `foto-${uuidv4().substring(0,8)}.jpg`;
        let mimeType = 'image/jpeg';

        if (!contentType) {
            return resolve({ statusCode: 400, body: JSON.stringify({error: "Falta Content-Type"}) });
        }

        // Si envían JSON con base64
        if (contentType.includes('application/json')) {
            try {
                const body = JSON.parse(event.isBase64Encoded ? Buffer.from(event.body, 'base64').toString('utf8') : event.body);
                if (body.image) imageBuffer = Buffer.from(body.image, 'base64');
            } catch(e) {
                return resolve({ statusCode: 400, body: "JSON Invalido" });
            }
            if (imageBuffer) {
                uploadToS3(imageBuffer, filename, mimeType)
                    .then(() => resolve({ statusCode: 200, body: JSON.stringify({ message: "Éxito", file: filename }) }))
                    .catch(e => resolve({ statusCode: 500, body: "Error en S3" }));
            }
        } 
        // Si envían formulario (multipart/form-data)
        else if (contentType.includes('multipart/form-data')) {
            const busboy = Busboy({ headers: { 'content-type': contentType } });
            
            busboy.on('file', (name, file, info) => {
                filename = `foto-${uuidv4().substring(0,8)}-${info.filename}`;
                mimeType = info.mimeType;
                const chunks = [];
                file.on('data', data => chunks.push(data));
                file.on('end', () => { imageBuffer = Buffer.concat(chunks); });
            });
            
            busboy.on('finish', async () => {
                if (!imageBuffer) return resolve({statusCode: 400, body: "No se encontro archivo"});
                try {
                    await uploadToS3(imageBuffer, filename, mimeType);
                    resolve({ statusCode: 200, body: JSON.stringify({ message: "Éxito", file: filename }) });
                } catch(e) {
                    resolve({ statusCode: 500, body: "Error en S3" });
                }
            });

            busboy.write(event.isBase64Encoded ? Buffer.from(event.body, 'base64') : Buffer.from(event.body));
            busboy.end();
        } else {
            resolve({ statusCode: 400, body: "Formato no soportado" });
        }
    });
};

async function uploadToS3(buffer, filename, mimeType) {
    const command = new PutObjectCommand({
        Bucket: BUCKET_NAME,
        Key: `${PREFIX}${filename}`,
        Body: buffer,
        ContentType: mimeType
    });
    return s3.send(command);
}