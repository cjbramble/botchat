# Who may take on this role: EC2, on behalf of the instance.
data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "instance" {
  name               = "botchat-instance"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "instance" {
  for_each = {
    ssm  = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore" # Session Manager
    game = aws_iam_policy.game_publisher.arn                      # from Step 11
    chat = aws_iam_policy.chat_consumer.arn                       # from Step 11
  }
  role       = aws_iam_role.instance.name
  policy_arn = each.value
}

# EC2 attaches roles through an "instance profile", a thin wrapper around the role.
resource "aws_iam_instance_profile" "instance" {
  name = "botchat-instance"
  role = aws_iam_role.instance.name
}
