CPAC Project
==============

# 1) Project description

This project is an interactive audiovisual installation designed to create a dynamic and immersive atmosphere that responds to human presence and behavior. It combines generative sound, real-time visuals, and machine learning to produce an environment that evolves according to a user's movements, facial expressions, and interactions with the computer.

The primary goal of the project is to provide a soothing and engaging experience, encouraging relaxation and momentary distraction from everyday stress. By continuously adapting its audiovisual output to the user's state and actions, the system creates a personalized sensory experience that feels alive and responsive.

Sound is generated in real time using **SuperCollider**, while **Processing** is responsible for the visual component. **Machine learning** models are used for movement, object, and facial expression recognition, enabling the system to perceive and interpret user behavior. Communication between the different modules is handled through **Python** and the **Open Sound Control (OSC)** protocol, ensuring seamless real-time interaction.

By bringing together sound synthesis, visual art, computer vision, and machine learning, this project explores new ways of creating interactive environments that promote calmness, curiosity, and well-being.



# 2) Project technical overview

The sound and visuals are meant to be changed live by the user. To that extent, we use computer sensors to collect data from user's behavior, such as facial expression or mouvements. The raw signal from those sensors are then interpreted by algorithms or machine learning models, to extract a set of inputs that will then be used by the audiovisual generation block to change the output live. The following figures shows the overall pipeline of the project.



![Project pipeline](resources/project_pipeline.png)


## a) Feature extraction from sensors

Three different types of features are extracted from sensors' raw signals. They are listed in the following table.


| Movement features             | Facial expression features    | Mouse/trackpad features    |
| :------------                 | :-----------                  | :-----------               |
| No movement (default)         | No expression (input)         | XY position                |
| Moving fingers                | Smile                         | Left/right click           |
| Moving left/right arm         | Angry                         |                            |
| Moving left/right hand        | Eyes closed                   |                            |
| One hand shape: 'OK' sign     |                               |                            |
| One hand shape: 'V' sign      |                               |                            |
| One hand shape: 'Punch' sign  |                               |                            |
| One hand shape: 'Heart' sign  |                               |                            |
| One hand shape: Thumbs up     |                               |                            |
| One hand shape: Thumbs down   |                               |                            |



For movement features, we use a motion tracking algorithm similar to the one saw in CPAC lab, to track arms, hands and fingers movements. As far as hand shapes are concerned, we will train a Support Vector Machine (SVM) using Python and Scikit-Learn. The training will be carried exactly as in the CPAC lab n°4: *Cognitive Agents*:

- we capture several pictures of the different hand shapes, which are later converted in black and white;
- we add the corresponding label to each of them;
- we train the SVM classification model.




*Missing: facial expression recognition*




Finally, mouse/trackpad features are the simplest to extract, as they do not need further processing and can be used as inputs as is.

## b) Feature tree

The main asset of the project is that a different feature-to-audiovisuals mapping is determined every time the project is ran. Therefore, the user never knows the exact consequences of their interactions with the system, and finding them cound represent another distracting asset of our project.


In order for the system to be even less predictible, we do not simply consider a matching between features and andiovisuals, but a matching between *combinations* of features and audiovisuals. These combinations are represented by a tree, like the one in the following figure.


![Feature tree](resources/feature_tree.png)


Each output is then mapped and converted to a specific OSC message, which is sent to SuperCollider and Processing for sound and visuals changes.



## c) Visuals generation


- particle systems (Boids, steering vectors with the use of the mouse XY position?)
- user's movements perturbates particle trajectories


## c) Sound generation


- use of attractors (Hénon, Gingerbreadman..) to generade melodies
- use of samples for real-life atmospheres (city, nature, sea...)
- 