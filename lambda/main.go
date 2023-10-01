package main

import (
	"errors"
	"fmt"
	"log"
	"time"
	"strings"

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
	object_key := request.RawPath
	key := `-----BEGIN RSA PRIVATE KEY-----
-----END RSA PRIVATE KEY-----
`
	object_url := fmt.Sprintf("https://dbj2ng6wjzi8r.cloudfront.net%s", object_key)

	keyReader := strings.NewReader(key)
	privKey, err := sign.LoadPEMPrivKey(keyReader)
	if err != nil {
		log.Fatal("failed to load priv key:", err)
	}
	signer := sign.NewURLSigner("KATAUHJIZTTOK", privKey)
	signedURL, err := signer.Sign(object_url, expireAt)
	if err != nil {
		log.Fatal("generate signed url failed:", err)
	}
	// stdout and stderr are sent to AWS CloudWatch Logs
	log.Printf("Processing Lambda request %s\n", request.RequestContext.RequestID)

	return events.APIGatewayV2HTTPResponse{
		Body:    "",
		Headers: map[string]string{"Location": signedURL},
		StatusCode: 302,
	}, nil

}

func main() {
	lambda.Start(Handler)
}
