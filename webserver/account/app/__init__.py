# -*- coding: utf-8 -*-
import os
from flask import Flask, request, jsonify, make_response, \
    flash, redirect, url_for, session, escape, g
from flask_sqlalchemy import SQLAlchemy

from app.database import db
from app.mod_user.controllers import userbp


def create_app(config=None):
    app = Flask(__name__)

    # If no config file is passed in on the command line:
    if config is None:
        config = os.path.join(app.root_path, os.environ.get('FLASK_APPLICATION_SETTINGS'))

    app.config.from_pyfile(config)

    # Secret key needed to use sessions.
    app.secret_key = app.config['SECRET_KEY']

    # Initialize SQL Alchemy and Flask-Login
    # Instantiate the Bcrypt extension
    db.init_app(app)


    # Automatically tear down SQLAlchemy
    @app.teardown_request
    def shutdown_session(exception=None):
        db.session.remove()

    app.register_blueprint(userbp)

    return app
