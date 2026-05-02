const { S3Client, PutObjectCommand } = require("@aws-sdk/client-s3");
const { v4: uuidv4 } = require("uuid");

const s3Client = new S3Client({});

exports.handler = async (event) => {
    try {
        // Validar Base64
        if (!event.body || !event.isBase64Encoded) {
            return { 
                statusCode: 400, 
                body: JSON.stringify({ message: "Error: Se espera una imagen en Base64." }) 
            };
        }

        // Decodificar la imagen a binario
        const imageBuffer = Buffer.from(event.body, 'base64');
        const fileName = `${uuidv4()}.jpg`; 
        
        // Variables de entorno inyectadas por Terraform
        const bucketName = process.env.S3_BUCKET;
        const prefix = process.env.UPLOAD_PREFIX; // "uploads/"

        // Subir a S3
        const command = new PutObjectCommand({
            Bucket: bucketName,
            Key: `${prefix}${fileName}`,
            Body: imageBuffer,
            ContentType: "image/jpeg"
        });

        await s3Client.send(command);

        return {
            statusCode: 200,
            body: JSON.stringify({ message: "Imagen subida exitosamente", file: fileName })
        };

    } catch (error) {
        console.error("Error:", error);
        return { statusCode: 500, body: JSON.stringify({ message: "Error interno" }) };
    }
};