package main

import (
	"errors"
	"fmt"
	"log"
	"os"
	"strings"
	"time"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"

	"github.com/aws/aws-sdk-go-v2/feature/cloudfront/sign"
)

var (
	// ErrNameNotProvided is thrown when a name is not provided
	ErrObjectNotFound = errors.New("requested object was not found in bucket")
)

// Handler is your Lambda function handler
// It uses Amazon API Gateway request/responses provided by the aws-lambda-go/events package,
// However you could use other event sources (S3, Kinesis etc), or JSON-decoded primitive types such as 'string'.
func Handler(request events.APIGatewayV2HTTPRequest) (events.APIGatewayV2HTTPResponse, error) {

	expireAt := time.Now().Add(90 * time.Minute)
	objectKey := request.RawPath
	key := os.Getenv("SIGNING_PRIVATE_KEY")
	id := os.Getenv("SIGNING_PUBLIC_ID")
	cloudfrontDomain := os.Getenv("CLOUDFRONT_DOMAIN")

	object_url := fmt.Sprintf("https://%s%s", cloudfrontDomain , objectKey)

	keyReader := strings.NewReader(key)
	privKey, err := sign.LoadPEMPrivKey(keyReader)
	if err != nil {
		log.Fatal("failed to load priv key:", err)
	}
	signer := sign.NewURLSigner(id, privKey)
	signedURL, err := signer.Sign(object_url, expireAt)
	if err != nil {
		log.Fatal("generate signed url failed:", err)
	}
	log.Printf("Signed URL: %s\n", signedURL)

	return events.APIGatewayV2HTTPResponse{
		Body:    "",
		Headers: map[string]string{"Location": signedURL},
		StatusCode: 302,
	}, nil

}

func main() {
	lambda.Start(Handler)
}
